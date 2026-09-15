#!/bin/bash
# ============================================
# envup — host-side clangd databases for Docker builds
# ============================================
# CMake writes absolute paths into compile_commands.json. When CMake runs in a
# bind-mounted container but nvim/clangd run on the host, those paths describe
# a filesystem that does not exist to clangd. This command derives the mapping
# from Docker itself and writes a translated copy under nvim's cache. It never
# edits the project's database and the cache keeps working after the container
# exits.
#
# Depends on: log.sh, fs.sh
# ============================================

_clangd_cache_root() {
    printf '%s/%s/envup/clangd\n' "${XDG_CACHE_HOME:-$HOME/.cache}" "${NVIM_APPNAME:-nvim}"
}

_clangd_project_root() {
    local path="${1:-$PWD}"
    [[ -f "$path" ]] && path="${path%/*}"
    path="$(_realpath "$path")"
    [[ -d "$path" ]] || { log_error "not a directory: $path"; return 1; }

    local root
    root="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" || root=""
    if [[ -n "$root" ]]; then _realpath "$root"; return; fi

    while [[ "$path" != / ]]; do
        [[ -f "$path/CMakeLists.txt" ]] && { printf '%s\n' "$path"; return; }
        path="${path%/*}"; [[ -n "$path" ]] || path=/
    done
    log_error "could not find a Git or CMake project above ${1:-$PWD}"
    return 1
}

_clangd_find_database() {
    local root="$1" explicit="${2:-}" configured="" path
    if [[ -n "$explicit" ]]; then
        [[ "$explicit" == /* ]] || explicit="$PWD/$explicit"
        path="$(_realpath "$explicit")"
        [[ -f "$path" ]] || { log_error "compile database not found: $path"; return 1; }
        printf '%s\n' "$path"
        return
    fi

    if [[ -r "$root/.clangd" ]]; then
        configured="$(sed -n 's/^[[:space:]]*CompilationDatabase:[[:space:]]*//p' "$root/.clangd" | head -1)"
        configured="${configured%\"}"; configured="${configured#\"}"
        configured="${configured%\'}"; configured="${configured#\'}"
        case "$configured" in
            ""|None|Ancestors) configured="" ;;
            /*) path="$configured/compile_commands.json" ;;
            *)  path="$root/$configured/compile_commands.json" ;;
        esac
        [[ -n "$configured" && -f "$path" ]] && { _realpath "$path"; return; }
    fi
    for path in "$root/compile_commands.json" "$root/build/compile_commands.json"; do
        [[ -f "$path" ]] && { _realpath "$path"; return; }
    done
    log_error "no compile_commands.json found for $root"
    log_hint "pass one explicitly with: envup clangd sync --database PATH"
    return 1
}

_clangd_cmake_value() {
    local cache="$1" key="$2"
    sed -n "s/^${key}:[^=]*=//p" "$cache" | head -1
}

_clangd_file_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null
}

_clangd_mounts() {
    local output="$1"; shift
    local -a ids=()
    mapfile -t ids < <(docker ps -aq 2>/dev/null)
    (( ${#ids[@]} )) || { log_error "Docker has no containers to inspect"; return 1; }
    docker inspect -f '{{range .Mounts}}{{printf "%s\t%s\t%s\t%s\t%s\n" $.Id $.Name $.Created .Source .Destination}}{{end}}' \
        "${ids[@]}" >"$output" || { log_error "could not inspect Docker mounts"; return 1; }
}

_clangd_candidate_maps() {
    local mounts="$1" id="$2" output="$3"
    awk -F '\t' -v id="$id" '$1 == id { print length($5) "\t" $5 "\t" $4 }' "$mounts" |
        sort -rn | cut -f2- >"$output"
}

_clangd_map_path() {
    local value="$1" mappings="$2" container host
    while IFS=$'\t' read -r container host; do
        case "$value" in
            "$container")   printf '%s\n' "$host"; return ;;
            "$container"/*) printf '%s%s\n' "$host" "${value#"$container"}"; return ;;
        esac
    done <"$mappings"
    printf '%s\n' "$value"
}

_clangd_select_container() {
    local mounts="$1" root="$2" container_root="$3" requested="${4:-}" database="$5"
    local id name created source destination canonical
    local -a ids=() names=() created_at=()
    while IFS=$'\t' read -r id name created source destination; do
        [[ "$destination" == "$container_root" ]] || continue
        canonical="$(_realpath "$source")"
        [[ "$canonical" == "$root" ]] || continue
        name="${name#/}"
        local seen=0 existing
        for existing in "${ids[@]+"${ids[@]}"}"; do [[ "$existing" == "$id" ]] && seen=1; done
        (( seen )) || { ids+=("$id"); names+=("$name"); created_at+=("$created"); }
    done <"$mounts"

    (( ${#ids[@]} )) || {
        log_error "no Docker container maps $root to $container_root"
        return 1
    }

    if [[ -n "$requested" ]]; then
        local i
        for ((i=0; i<${#ids[@]}; i++)); do
            if [[ "${ids[$i]}" == "$requested"* || "${names[$i]}" == "$requested" ]]; then
                printf '%s\t%s\n' "${ids[$i]}" "${names[$i]}"
                return
            fi
        done
        log_error "container '$requested' does not provide this build's source mount"
        return 1
    fi

    if (( ${#ids[@]} == 1 )); then
        printf '%s\t%s\n' "${ids[0]}" "${names[0]}"
        return
    fi

    # Task containers usually configure CMake immediately after they are
    # created. An exact UTC-minute match is a strong, path-independent signal
    # and resolves the common case without guessing between old task containers
    # that happen to mount the same checkout. Anything less precise remains an
    # explicit ambiguity.
    local epoch minute="" matched=-1 matches=0
    if epoch="$(stat -c %Y "$database" 2>/dev/null)"; then
        minute="$(date -u -d "@$epoch" +%Y-%m-%dT%H:%M 2>/dev/null || true)"
    elif epoch="$(stat -f %m "$database" 2>/dev/null)"; then
        minute="$(date -u -r "$epoch" +%Y-%m-%dT%H:%M 2>/dev/null || true)"
    fi
    if [[ -n "$minute" ]]; then
        local i
        for ((i=0; i<${#ids[@]}; i++)); do
            if [[ "${created_at[$i]:0:16}" == "$minute" ]]; then
                matched=$i; matches=$((matches + 1))
            fi
        done
        if (( matches == 1 )); then
            printf '%s\t%s\n' "${ids[$matched]}" "${names[$matched]}"
            return
        fi
    fi

    log_error "more than one Docker environment can explain this compile database"
    local i
    for ((i=0; i<${#ids[@]}; i++)); do printf '  %s  %s\n' "${ids[$i]:0:12}" "${names[$i]}" >&2; done
    log_hint "select the build environment once with: envup clangd sync --container NAME"
    return 1
}

_clangd_index_set() {
    local index="$1" root="$2" database="$3" drivers="$4" id="$5" name="$6" source_db="$7" source_mtime="$8"
    local tmp line existing
    mkdir -p "${index%/*}" || return 1
    tmp="$(mktemp "$index.tmp.XXXXXX")" || return 1
    if [[ -r "$index" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            existing="${line%%$'\t'*}"
            [[ "$existing" == "$root" ]] || printf '%s\n' "$line"
        done <"$index" >"$tmp"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$root" "$database" "$drivers" "$id" "$name" "$source_db" "$source_mtime" >>"$tmp"
    mv -f "$tmp" "$index"
}

_clangd_index_record() {
    local root="$1" index line
    index="$(_clangd_cache_root)/index.tsv"
    [[ -r "$index" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "${line%%$'\t'*}" == "$root" ]] && { printf '%s\n' "$line"; return; }
    done <"$index"
    return 1
}

_clangd_sync() {
    local requested="" explicit_db="" target="" dry=0
    while (($#)); do case "$1" in
        --container) requested="${2:-}"; [[ -n "$requested" ]] || { log_error "--container needs a name or ID"; return 1; }; shift 2 ;;
        --database) explicit_db="${2:-}"; [[ -n "$explicit_db" ]] || { log_error "--database needs a path"; return 1; }; shift 2 ;;
        -n|--dry-run) dry=1; shift ;;
        -h|--help) cat <<EOF
Usage: envup clangd sync [--container NAME] [--database FILE] [-n] [PATH]
  Convert a Docker-generated compile database for host-side clangd.
  PATH defaults to the current project. Docker mount paths are auto-discovered.
EOF
            return ;;
        -*) log_error "unknown option: $1"; return 1 ;;
        *) [[ -z "$target" ]] || { log_error "only one project path may be given"; return 1; }; target="$1"; shift ;;
    esac; done

    log_init clangd-sync || return 1

    have docker || { log_error "docker is required for clangd sync"; return 1; }
    have nvim || { log_error "nvim is required to translate the JSON database safely"; return 1; }

    local root database build_dir cache old_root selection id name tmp mounts maps
    root="$(_clangd_project_root "${target:-$PWD}")" || return 1
    database="$(_clangd_find_database "$root" "$explicit_db")" || return 1
    build_dir="${database%/*}"; cache="$build_dir/CMakeCache.txt"
    [[ -r "$cache" ]] || { log_error "CMakeCache.txt not found beside $database"; return 1; }
    old_root="$(_clangd_cmake_value "$cache" CMAKE_HOME_DIRECTORY)"
    [[ -n "$old_root" ]] || { log_error "CMAKE_HOME_DIRECTORY is missing from $cache"; return 1; }

    if [[ "$(_realpath "$old_root")" == "$root" && -d "$old_root" ]]; then
        log_info "compile database already uses the host project path: $root"
        return 0
    fi

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/envup-clangd.XXXXXX")" || return 1
    mounts="$tmp/mounts.tsv"; maps="$tmp/maps.tsv"
    _clangd_mounts "$mounts" || { rm -rf "$tmp"; return 1; }
    selection="$(_clangd_select_container "$mounts" "$root" "$old_root" "$requested" "$database")" || { rm -rf "$tmp"; return 1; }
    IFS=$'\t' read -r id name <<<"$selection"
    _clangd_candidate_maps "$mounts" "$id" "$maps"

    local cache_root key project_name output compiler mapped drivers="" value
    cache_root="$(_clangd_cache_root)"
    project_name="$(basename "$root")"
    project_name="$(printf '%s' "$project_name" | tr -c 'A-Za-z0-9._-' '_')"
    key="$project_name-$(printf '%s' "$root" | cksum | awk '{print $1}')"
    output="$cache_root/$key/compile_commands.json"

    if (( dry )); then
        log_info "[dry-run] translate $database -> $output"
        log_info "[dry-run] Docker environment: $name (${id:0:12})"
        rm -rf "$tmp"
        return
    fi

    mkdir -p "${output%/*}" || { rm -rf "$tmp"; return 1; }
    nvim --clean --headless -l "$ENVUP_HOME/scripts/clangd-cdb.lua" "$database" "$output" "$maps" || {
        log_error "could not translate $database"; rm -rf "$tmp"; return 1;
    }

    for value in CMAKE_C_COMPILER CMAKE_CXX_COMPILER CMAKE_HIP_COMPILER; do
        compiler="$(_clangd_cmake_value "$cache" "$value")"
        [[ -n "$compiler" ]] || continue
        mapped="$(_clangd_map_path "$compiler" "$maps")"
        [[ -x "$mapped" ]] || continue
        case ",$drivers," in *",$mapped,"*) ;; *) drivers="${drivers:+$drivers,}$mapped" ;; esac
    done

    _clangd_index_set "$cache_root/index.tsv" "$root" "$output" "$drivers" "$id" "$name" "$database" \
        "$(_clangd_file_mtime "$database")" || {
        log_error "could not update clangd cache index"; rm -rf "$tmp"; return 1;
    }
    rm -rf "$tmp"
    log_success "clangd database synced for $root"
    log_info "Docker environment: $name (${id:0:12})"
    log_info "Host database: $output"
    log_hint "restart the client with :LspRestart"
}

_clangd_status() {
    local root record database drivers id name source recorded_mtime current_mtime
    root="$(_clangd_project_root "${1:-$PWD}")" || return 1
    record="$(_clangd_index_record "$root")" || {
        log_info "no envup clangd database for $root"
        log_hint "run: envup clangd sync"
        return 1
    }
    IFS=$'\t' read -r _ database drivers id name source recorded_mtime <<<"$record"
    [[ -r "$database" ]] || { log_error "cached database is missing: $database"; return 1; }
    log_success "clangd database ready for $root"
    log_info "Host database: $database"
    log_info "Source database: $source"
    log_info "Docker environment: $name (${id:0:12})"
    [[ -n "$drivers" ]] && log_info "Trusted drivers: $drivers"
    current_mtime="$(_clangd_file_mtime "$source" 2>/dev/null || true)"
    if [[ -n "$recorded_mtime" && -n "$current_mtime" && "$recorded_mtime" != "$current_mtime" ]]; then
        log_warn "the Docker compile database changed after the last sync"
        log_hint "refresh it with: envup clangd sync${name:+ --container $name}"
        return 1
    fi
}

_clangd_clean() {
    local root record database index tmp line existing cache_root
    log_init clangd-clean || return 1
    root="$(_clangd_project_root "${1:-$PWD}")" || return 1
    cache_root="$(_clangd_cache_root)"; index="$cache_root/index.tsv"
    record="$(_clangd_index_record "$root")" || { log_info "no envup clangd cache for $root"; return; }
    IFS=$'\t' read -r _ database _ <<<"$record"
    case "$database" in "$cache_root"/*/compile_commands.json) ;; *) log_error "refusing unexpected cache path: $database"; return 1 ;; esac
    rm -rf "${database%/*}"
    tmp="$(mktemp "$index.tmp.XXXXXX")" || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        existing="${line%%$'\t'*}"
        [[ "$existing" == "$root" ]] || printf '%s\n' "$line"
    done <"$index" >"$tmp"
    mv -f "$tmp" "$index"
    log_success "removed clangd cache for $root"
}

clangd_main() {
    local action="${1:-status}"; (($#)) && shift
    case "$action" in
        sync)   _clangd_sync "$@" ;;
        status) [[ "${1:-}" == -h || "${1:-}" == --help ]] && { echo "Usage: envup clangd status [PATH]"; return; }; _clangd_status "$@" ;;
        clean)  [[ "${1:-}" == -h || "${1:-}" == --help ]] && { echo "Usage: envup clangd clean [PATH]"; return; }; _clangd_clean "$@" ;;
        -h|--help|help) cat <<EOF
Usage: envup clangd <action> [options]
  sync    Convert a Docker compile database for host-side clangd
  status  Show the database selected for the current project
  clean   Remove the current project's translated database
EOF
            ;;
        *) log_error "unknown clangd action: $action"; return 1 ;;
    esac
}
