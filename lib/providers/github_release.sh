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
# _ghr_pin <module> — the tag from versions.lock, if this module is pinned.
_ghr_pin() {
    local f="$ENVUP_HOME/versions.lock"
    [[ -f "$f" ]] || return 1
    awk -v m="$1" '$1 == m && $2 != "" { print $2; hit = 1; exit } END { exit !hit }' "$f"
}

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

# _ghr_place_bins <extract-dir> <binary>... — validate every requested binary
# before installing any, so a companion command cannot be missed silently.
_ghr_place_bins() {
    local d="$1"; shift
    local stage="$d/.envup-bins" b found
    mkdir -p "$stage"
    for b in "$@"; do
        found="$(find "$d" -path "$stage" -prune -o -type f -name "$b" -print 2>/dev/null | head -1)"
        [[ -n "$found" ]] || { log_error "[$NAME] no '$b' inside the release archive"; return 1; }
        cp "$found" "$stage/$b" && chmod 0755 "$stage/$b" || return 1
    done
    mkdir -p "$ENVUP_LOCAL_BIN"
    for b in "$@"; do
        install -m 0755 "$stage/$b" "$ENVUP_LOCAL_BIN/$b" 2>/dev/null \
            || { cp -f "$stage/$b" "$ENVUP_LOCAL_BIN/$b" && chmod 0755 "$ENVUP_LOCAL_BIN/$b"; } \
            || { log_error "[$NAME] could not write $ENVUP_LOCAL_BIN/$b"; return 1; }
    done
}

# _ghr_place_tree <extract-dir> — for releases that are a whole prefix.
_ghr_place_tree() {
    local d="$1" root sub
    # Archives normally hold a single top directory; use it if so.
    root="$d"
    sub="$(find "$d" -mindepth 1 -maxdepth 1 -print 2>/dev/null)"
    [[ "$(wc -l <<<"$sub")" == 1 && -d "$sub" ]] && root="$sub"

    local dest new old
    dest="$ENVUP_LOCAL_OPT/$NAME"
    new="$dest.new.$$"
    old="$dest.old.$$"
    mkdir -p "$ENVUP_LOCAL_OPT" "$ENVUP_LOCAL_BIN"
    rm -rf "$new" "$old"

    # Stage then swap so a failed cross-filesystem move preserves the old tree.
    mv "$root" "$new" || { rm -rf "$new"; log_error "[$NAME] could not stage $dest"; return 1; }
    if [[ -e "$dest" ]]; then
        mv "$dest" "$old" || { rm -rf "$new"; log_error "[$NAME] could not replace $dest"; return 1; }
    fi
    if ! mv "$new" "$dest"; then
        [[ -e "$old" ]] && mv "$old" "$dest"
        rm -rf "$new"; log_error "[$NAME] could not install into $dest"; return 1
    fi
    rm -rf "$old"

    local f n=0
    for f in "$dest"/bin/*; do
        [[ -f "$f" && -x "$f" ]] || continue
        ln -sf "$f" "$ENVUP_LOCAL_BIN/$(basename "$f")" && n=$((n + 1))
    done
    (( n )) || { log_error "[$NAME] $dest has no bin/ to link"; return 1; }

    # Remove links to binaries dropped by the new release tree.
    local l
    for l in "$ENVUP_LOCAL_BIN"/*; do
        [[ -L "$l" && ! -e "$l" ]] || continue
        [[ "$(readlink "$l")" == "$dest"/* ]] || continue
        rm -f "$l" && log_debug "[$NAME] removed stale link $(basename "$l")"
    done
    log_debug "[$NAME] linked $n binaries from $dest/bin"
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
    export PATH="$ENVUP_LOCAL_BIN:$PATH"
    case ":${PATH_ORIG:-$PATH}:" in
        *":$ENVUP_LOCAL_BIN:"*) ;;
        *) log_once local_bin_path log_warn "$ENVUP_LOCAL_BIN is where envup installs user-space tools — make sure it is on your PATH" ;;
    esac
    log_success "[$NAME] $bin ${_GHR_TAG:+$_GHR_TAG }installed to $ENVUP_LOCAL_BIN"
}
