#!/bin/bash
# Install a compatible prebuilt GitHub release into user space.
#   GH_REPO   owner/name                       (or the provider argument)
#   GH_TAG    release tag override             (default: versions.lock)
#   GH_BIN    binary inside the archive        (default VERIFY_BIN)
#   GH_BINS   all binaries to install from one archive; first selects the asset
#   GH_TREE   1 = the release is a directory tree, not a lone binary. Installs
#             under ~/.local/opt/<module> and links its bin/* — nvim needs this
#             because it will not start without its runtime/ directory.
#   GH_ASSET_AVOID  tokens marking a deliberately reduced build of the same
#             tool, so the full one wins the tie (eza's _no_libgit).
# versions.lock supplies the default tag when present.

ENVUP_LOCAL_OPT="${ENVUP_LOCAL_OPT:-$HOME/.local/opt}"

# ---- which release -------------------------------------------------------
# Print the tag first, then assets; fall back from API to release-page HTML.
_ghr_urls() {
    local repo="$1" tag="$2" json html path
    local api="https://api.github.com/repos/$repo/releases/latest"
    [[ -n "$tag" ]] && api="https://api.github.com/repos/$repo/releases/tags/$tag"

    json="$(net_fetch "$api" - 2>/dev/null)" || json=""
    if [[ "$json" == *browser_download_url* ]]; then
        printf '%s\n' "$(grep -o '"tag_name":[[:space:]]*"[^"]*"' <<<"$json" | head -1 | sed 's/.*"\(.*\)"/\1/')"
        grep -oE 'https://[^"]+/releases/download/[^"]+' <<<"$json" | sort -u
        return 0
    fi

    log_debug "[$NAME] GitHub API unusable here; reading the release page instead"
    if [[ -z "$tag" ]]; then
        html="$(net_fetch "https://github.com/$repo/releases/latest" - 2>/dev/null)" || return 1
        tag="$(grep -oE "/$repo/releases/tag/[^\"']+" <<<"$html" | head -1 | sed 's|.*/||')"
        [[ -n "$tag" ]] || return 1
    fi
    printf '%s\n' "$tag"

    html="$(net_fetch "https://github.com/$repo/releases/expanded_assets/$tag" - 2>/dev/null)" || return 1
    while IFS= read -r path; do
        printf 'https://github.com%s\n' "$path"
    done < <(grep -oE "/$repo/releases/download/[^\"']+" <<<"$html" | sort -u)
}

# ---- which asset ---------------------------------------------------------
_ghr_tok_match() {   # <haystack> <token>... : true if any token appears
    local hay="$1"; shift
    local t; for t in "$@"; do [[ "$hay" == *"$t"* ]] && return 0; done
    return 1
}

# Reject sibling products such as atuin-server when installing atuin.
_ghr_wrong_artifact() {
    local base="$1" want="$2" rest t
    [[ -n "$want" && "$base" == "$want"* ]] || return 1
    rest="${base#"$want"}"; rest="${rest#[-_.]}"
    [[ -n "$rest" ]] || return 1
    # A valid suffix begins with a version, OS, or architecture token.
    [[ "$rest" =~ ^v?[0-9] ]] && return 1
    for t in "${os_tok[@]}" "${arch_tok[@]}"; do
        [[ "$rest" == "$t"* ]] && return 1
    done
    return 0
}

_ghr_pick() {
    local -a os_tok arch_tok
    local want="${GH_BIN:-${VERIFY_BIN:-}}"
    if declare -p GH_BINS >/dev/null 2>&1 && (( ${#GH_BINS[@]} )); then
        want="${GH_BINS[0]}"
    fi
    want="$(tr '[:upper:]' '[:lower:]' <<<"$want")"
    case "$ENVUP_OS" in
        macos) os_tok=(darwin macos osx) ;;
        linux) os_tok=(linux) ;;
        *)     os_tok=("$ENVUP_OS") ;;
    esac
    case "$ENVUP_ARCH" in
        x86_64)  arch_tok=(x86_64 amd64 x64 64-bit 64bit) ;;
        aarch64) arch_tok=(aarch64 arm64) ;;
        armv7)   arch_tok=(armv7 armhf) ;;
        i686)    arch_tok=(i686 i386 386) ;;
        *)       arch_tok=("$ENVUP_ARCH") ;;
    esac

    local url base score best="" bestscore=-1
    while IFS= read -r url; do
        [[ -n "$url" ]] || continue
        base="$(tr '[:upper:]' '[:lower:]' <<<"${url##*/}")"
        case "$base" in
            # Metadata and signatures are not installable assets.
            *.sha256|*.sha256sum|*.sha512|*.asc|*.sig|*.minisig|*.pem|*.sbom|*.json|*.txt|*.md) continue ;;
            # System packages belong to the system provider.
            *.deb|*.rpm|*.apk|*.pkg|*.dmg|*.msi|*.exe|*.appimage) continue ;;
            *source*|*sources*|*.src.*) continue ;;
        esac
        _ghr_tok_match "$base" "${os_tok[@]}"   || continue
        _ghr_tok_match "$base" "${arch_tok[@]}" || continue

        score=1
        case "$ENVUP_LIBC" in
            musl)   [[ "$base" == *musl* ]] && score=$((score + 4)) ;;
            glibc*) if [[ "$base" == *musl* ]]; then score=$((score + 1))   # static: always safe
                    else                              score=$((score + 2)); fi ;;
        esac
        # Only count formats we can actually unpack on this machine.
        case "$base" in
            *.tar.gz|*.tgz)      score=$((score + 3)) ;;
            *.tar.xz)            have xz && score=$((score + 3)) || continue ;;
            *.tar.bz2)           score=$((score + 2)) ;;
            *.zip)               have unzip && score=$((score + 2)) || continue ;;
            *.tar.*|*.7z|*.rar)  continue ;;
            *)                   score=$((score + 2)) ;;   # a bare binary is fine too
        esac
        _ghr_wrong_artifact "$base" "$want" && score=$((score - 4))

        # Penalize reduced builds without making them unusable as a last resort.
        local avoid
        for avoid in ${GH_ASSET_AVOID[@]+"${GH_ASSET_AVOID[@]}"}; do
            [[ "$base" == *"$avoid"* ]] && score=$((score - 3))
        done

        if (( score > bestscore )); then bestscore=$score; best="$url"; fi
    done
    [[ -n "$best" ]] || return 1
    printf '%s' "$best"
}

# ---- unpacking -----------------------------------------------------------
_ghr_extract() {   # <archive> <into-dir>
    local f="$1" d="$2"
    case "$(tr '[:upper:]' '[:lower:]' <<<"$f")" in
        *.tar.gz|*.tgz)  tar -xzf "$f" -C "$d" ;;
        *.tar.xz)        tar -xJf "$f" -C "$d" 2>/dev/null || { xz -dc "$f" | tar -xf - -C "$d"; } ;;
        *.tar.bz2)       tar -xjf "$f" -C "$d" ;;
        *.zip)           unzip -q "$f" -d "$d" ;;
        *)               return 2 ;;    # not an archive: a bare binary
    esac
}

# Probe absolute candidate paths so an older tool on PATH cannot hide a bad release.
_ghr_verify_bins() {
    local d="$1" b out v; shift
    for b in "$@"; do
        [[ -f "$d/$b" && -x "$d/$b" ]] || return 1
        # shellcheck disable=SC2086
        out="$(NVIM_LOG_FILE=/dev/null "$d/$b" ${VERIFY_VERSION_ARG:---version} 2>&1)" || {
            log_error "[$NAME] candidate $d/$b cannot run"; return 1;
        }
        if [[ "$b" == "${VERIFY_BIN:-}" && -n "${VERIFY_MIN_VERSION:-}" ]]; then
            v="$(printf '%s\n' "$out" | head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
            [[ -n "$v" ]] && version_ge "$v" "$VERIFY_MIN_VERSION" || {
                log_error "[$NAME] candidate $b does not meet $VERIFY_MIN_VERSION"; return 1;
            }
        fi
        if [[ "$b" == "${VERIFY_BIN:-}" && -n "${_ENG_TARGET_VERSION:-}" ]]; then
            v="$(printf '%s\n' "$out" | head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1)"
            [[ -n "$v" ]] && version_ge "$v" "$_ENG_TARGET_VERSION" && version_ge "$_ENG_TARGET_VERSION" "$v" || {
                log_error "[$NAME] candidate $b does not match locked $_ENG_TARGET_VERSION"; return 1;
            }
        fi
    done
}

# A release may replace a tree and several links. Keep every old entry until
# all moves and the probes at the final paths succeed. Empty sources remove links.
_ghr_activate() (
    local txn="$1" verify_dir="$2"; shift 2
    local -a bins=() targets=()
    while [[ "$1" != -- ]]; do bins+=("$1"); shift; done
    shift
    local src dst i=0 failed=0 interrupted=0
    _ghr_restore() {
        local j target backup
        for (( j=${#targets[@]}-1; j>=0; j-- )); do
            target="${targets[j]}"; backup="$txn/old/$j"
            if ! rm -rf "$target" ||
               { [[ -e "$backup" || -L "$backup" ]] && ! mv "$backup" "$target"; }; then
                log_error "[$NAME] could not restore $target; backup retained in $txn"
                failed=1
            fi
        done
        if (( failed == 0 )); then
            rm -rf "$txn"
            log_error "[$NAME] release activation failed; previous entries restored"
        fi
    }
    trap _ghr_restore EXIT
    # Defer exit until the completed move is recorded for recovery.
    trap 'interrupted=130' INT
    trap 'interrupted=143' TERM
    trap 'interrupted=129' HUP
    mkdir -p "$txn/old" || exit 1
    while (( $# )); do
        src="$1"; dst="$2"; shift 2
        if [[ -e "$dst" || -L "$dst" ]]; then
            mv "$dst" "$txn/old/$i" || exit 1
        fi
        targets+=("$dst"); i=$((i+1))
        (( interrupted == 0 )) || exit "$interrupted"
        [[ -z "$src" ]] || mv "$src" "$dst" || exit 1
        (( interrupted == 0 )) || exit "$interrupted"
    done
    _ghr_verify_bins "$verify_dir" "${bins[@]}" || exit 1
    (( interrupted == 0 )) || exit "$interrupted"
    trap - EXIT INT TERM HUP
    rm -rf "$txn" || log_warn "[$NAME] release installed; could not remove backup $txn"
)

# Stage on the destination filesystem before replacing any executable.
_ghr_place_bins() {
    local d="$1"; shift
    local txn stage b found
    local -a moves=()
    mkdir -p "$ENVUP_LOCAL_BIN" || return 1
    txn="$(mktemp -d "$ENVUP_LOCAL_BIN/.envup-$NAME.XXXXXX")" || return 1
    stage="$txn/new"
    mkdir -p "$stage" || { rm -rf "$txn"; return 1; }
    for b in "$@"; do
        found="$(find "$d" -type f -name "$b" -print 2>/dev/null | head -1)"
        if [[ -z "$found" || -d "$ENVUP_LOCAL_BIN/$b" ]] ||
           ! { cp "$found" "$stage/$b" && chmod 0755 "$stage/$b"; }; then
            log_error "[$NAME] could not prepare '$b' from the release archive"
            rm -rf "$txn"; return 1
        fi
        moves+=("$stage/$b" "$ENVUP_LOCAL_BIN/$b")
    done
    _ghr_verify_bins "$stage" "$@" || { rm -rf "$txn"; return 1; }
    _ghr_activate "$txn" "$ENVUP_LOCAL_BIN" "$@" -- "${moves[@]}"
}

# _ghr_place_tree <extract-dir> — for releases that are a whole prefix.
_ghr_place_tree() {
    local d="$1" root sub
    # Archives normally hold a single top directory; use it if so.
    root="$d"
    sub="$(find "$d" -mindepth 1 -maxdepth 1 -print 2>/dev/null)"
    [[ "$(wc -l <<<"$sub")" == 1 && -d "$sub" ]] && root="$sub"

    local dest txn new f b l
    local -a bins=() moves=()
    dest="$ENVUP_LOCAL_OPT/$NAME"
    mkdir -p "$ENVUP_LOCAL_OPT" "$ENVUP_LOCAL_BIN" || return 1
    txn="$(mktemp -d "$dest.envup.XXXXXX")" || return 1
    new="$txn/new"
    mv "$root" "$new" || { rm -rf "$txn"; log_error "[$NAME] could not stage $dest"; return 1; }
    moves+=("$new" "$dest")
    for f in "$new"/bin/*; do
        [[ -f "$f" && -x "$f" ]] || continue
        b="$(basename "$f")"; bins+=("$b")
        if [[ -d "$ENVUP_LOCAL_BIN/$b" ]] || ! ln -s "$dest/bin/$b" "$txn/$b"; then
            rm -rf "$txn"; log_error "[$NAME] could not prepare link for $b"; return 1
        fi
        moves+=("$txn/$b" "$ENVUP_LOCAL_BIN/$b")
    done
    if (( ${#bins[@]} == 0 )) ||
       { [[ -n "${VERIFY_BIN:-}" ]] && [[ ! -x "$new/bin/$VERIFY_BIN" ]]; }; then
        rm -rf "$txn"; log_error "[$NAME] release has no required bin/ to link"; return 1
    fi
    _ghr_verify_bins "$new/bin" "${bins[@]}" || { rm -rf "$txn"; return 1; }
    # Only remove obsolete links owned by this prefix, within the same recovery.
    for l in "$ENVUP_LOCAL_BIN"/*; do
        [[ -L "$l" ]] || continue
        [[ "$(readlink "$l")" == "$dest"/* ]] || continue
        [[ -e "$new/bin/$(basename "$l")" ]] || moves+=("" "$l")
    done
    _ghr_activate "$txn" "$dest/bin" "${bins[@]}" -- "${moves[@]}"
}

# ---- the provider --------------------------------------------------------
provider_github_release() {
    local repo="${1:-$GH_REPO}" bin="${GH_BIN:-$VERIFY_BIN}"
    local -a bins=()
    if declare -p GH_BINS >/dev/null 2>&1 && (( ${#GH_BINS[@]} )); then
        bins=("${GH_BINS[@]}")
    else
        bins=("$bin")
    fi
    [[ -n "$repo" ]] || { log_error "[$NAME] github_release provider needs GH_REPO"; return 1; }
    [[ -n "${bins[0]}" ]] || { log_error "[$NAME] github_release provider needs GH_BIN, GH_BINS or VERIFY_BIN"; return 1; }

    if ! have tar && ! have unzip; then
        log_debug "[$NAME] neither tar nor unzip; cannot unpack a release"
        return "$ENVUP_RC_UNAVAIL"
    fi
    if [[ "${ENVUP_DRY_RUN:-0}" == 1 ]]; then
        log_info "[dry-run] would install $bin from github.com/$repo into $ENVUP_LOCAL_BIN"; return 0
    fi
    if ! net_online; then
        log_debug "[$NAME] offline; cannot reach github releases"
        return "$ENVUP_RC_UNAVAIL"
    fi

    local tag="${GH_TAG:-}"
    if [[ -n "$tag" ]]; then
        log_info "[$NAME] using compatible release $tag"
    else
        tag="$(_ghr_pin "$NAME")" || tag=""
        [[ -n "$tag" ]] && log_info "[$NAME] pinned by versions.lock to $tag"
    fi

    local -a urls=()
    mapfile -t urls < <(_ghr_urls "$repo" "$tag")
    if (( ${#urls[@]} < 2 )); then
        log_warn "[$NAME] could not list release assets for $repo"
        log_hint "behind a proxy that blocks github? set ENVUP_GH_MIRROR, or pin a version in versions.lock"
        return 1
    fi
    _GHR_TAG="${urls[0]}"; urls=("${urls[@]:1}")

    local asset; asset="$(printf '%s\n' "${urls[@]}" | _ghr_pick)" || {
        log_warn "[$NAME] $repo ${_GHR_TAG:-latest} has no asset for $ENVUP_OS/$ENVUP_ARCH ($ENVUP_LIBC)"
        return "$ENVUP_RC_UNAVAIL"
    }
    log_info "[$NAME] release ${_GHR_TAG:-latest}: $(basename "$asset")"

    local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/envup-$NAME.XXXXXX")" || return 1
    local file="$tmp/$(basename "${asset%%\?*}")" rc=0
    if ! net_fetch "$asset" "$file"; then
        rm -rf "$tmp"; log_error "[$NAME] download failed: $asset"; return 1
    fi

    if ! net_check_asset "$NAME" "$file" "$asset" "$tmp" "${urls[@]}"; then
        rm -rf "$tmp"
        log_hint "a mirror can hand back a stale or truncated file — retry without ENVUP_GH_MIRROR, or pin a known-good tag in versions.lock"
        return 1
    fi

    mkdir -p "$tmp/x"
    _ghr_extract "$file" "$tmp/x"; rc=$?
    if (( rc == 2 )); then                       # a bare binary, not an archive
        chmod +x "$file"; mkdir -p "$tmp/x"; mv "$file" "$tmp/x/$bin"; rc=0
    fi
    if (( rc != 0 )); then
        rm -rf "$tmp"; log_error "[$NAME] could not unpack $(basename "$file")"; return 1
    fi

    if [[ "${GH_TREE:-0}" == 1 ]]; then
        _ghr_place_tree "$tmp/x"; rc=$?
    else
        _ghr_place_bins "$tmp/x" "${bins[@]}"; rc=$?
    fi
    rm -rf "$tmp"
    (( rc == 0 )) || return "$rc"

    # Make freshly installed binaries visible to this process's verify step.
    local visible; visible="$(command -v "$VERIFY_BIN" 2>/dev/null)" || visible=""
    export PATH="$ENVUP_LOCAL_BIN:$PATH"
    [[ "$visible" == "$ENVUP_LOCAL_BIN/$VERIFY_BIN" ]] ||
        log_once local_bin_path log_warn "user PATH resolves $VERIFY_BIN to ${visible:-no command}; put $ENVUP_LOCAL_BIN first to use the installed release"
    log_success "[$NAME] $bin ${_GHR_TAG:+$_GHR_TAG }installed to $ENVUP_LOCAL_BIN"
}
