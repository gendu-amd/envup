#!/bin/bash
# ============================================
# provider: github_release — a prebuilt binary into ~/.local/bin
# ============================================
# This is the one that makes envup usable on a server where you are not root.
# zoxide, atuin, fzf, nvim and friends all ship static binaries for exactly the
# platforms envup runs on; before this provider existed the only routes were a
# package manager we couldn't invoke and a vendor script that assumed it could
# write wherever it liked, so a no-sudo machine got nothing at all.
#
#   GH_REPO   owner/name                       (or the provider argument)
#   GH_BIN    binary inside the archive        (default VERIFY_BIN)
#   GH_TREE   1 = the release is a directory tree, not a lone binary. Installs
#             under ~/.local/opt/<module> and links its bin/* — nvim needs this
#             because it will not start without its runtime/ directory.
#
# The version is pinned in versions.lock when an entry exists. That is what
# makes several machines agree: without a pin, two servers set up a week apart
# get different builds and the difference shows up as a mystery later.
#
# Depends on: engine.sh, net.sh, caps.sh
# ============================================

ENVUP_LOCAL_OPT="${ENVUP_LOCAL_OPT:-$HOME/.local/opt}"

# ---- which release -------------------------------------------------------
# _ghr_pin <module> — the tag from versions.lock, if this module is pinned.
_ghr_pin() {
    local f="$ENVUP_HOME/versions.lock"
    [[ -f "$f" ]] || return 1
    awk -v m="$1" '$1 == m && $2 != "" { print $2; hit = 1; exit } END { exit !hit }' "$f"
}

# _ghr_urls <repo> <tag|""> — print the tag on the first line, then one asset
# URL per line. The tag rides in the output rather than in a variable because
# every caller reads this through `mapfile < <(...)`, and a subshell cannot
# hand a variable back — which is how the release tag used to come out empty in
# the "installed" line and, worse, in the manifest.
#
# The API is tried first because it answers both questions in one request, then
# the release page, which is plain HTML and therefore survives mirrors that only
# proxy github.com and know nothing about api.github.com.
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

# _ghr_pick — read candidate URLs on stdin, print the best one for this machine.
# Scoring rather than a first-match rule, because a release commonly carries a
# gnu build and a musl build of the same thing and the right answer depends on
# the machine's libc — the reason a binary that "works on my laptop" dies on an
# older server with "GLIBC_2.32 not found".
# _ghr_wrong_artifact <base> <want> — true when this asset is a *sibling*
# product rather than the tool itself. atuin's release carries both
# atuin-x86_64-...tar.gz and atuin-server-x86_64-...tar.gz; they score
# identically on os/arch/format, so without this the server binary wins on
# nothing more than alphabetical order — and installs cleanly, which is the
# worst way to be wrong.
_ghr_wrong_artifact() {
    local base="$1" want="$2" rest t
    [[ -n "$want" && "$base" == "$want"* ]] || return 1
    rest="${base#"$want"}"; rest="${rest#[-_.]}"
    [[ -n "$rest" ]] || return 1
    # Whatever follows the tool's name has to be platform detail — a version, an
    # OS or an architecture. Anything else is a different product from the same
    # release: -server, -cli, -completions, -docs.
    #
    # Matched as a prefix of the remainder rather than by splitting on the first
    # separator, because "x86_64" contains one and splitting turns it into the
    # unrecognisable "x86".
    [[ "$rest" =~ ^v?[0-9] ]] && return 1
    for t in "${os_tok[@]}" "${arch_tok[@]}"; do
        [[ "$rest" == "$t"* ]] && return 1
    done
    return 0
}

_ghr_pick() {
    local -a os_tok arch_tok
    local want; want="$(tr '[:upper:]' '[:lower:]' <<<"${GH_BIN:-${VERIFY_BIN:-}}")"
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
            # checksums, signatures, metadata: not the thing we came for
            *.sha256|*.sha256sum|*.sha512|*.asc|*.sig|*.minisig|*.pem|*.sbom|*.json|*.txt|*.md) continue ;;
            # OS packages need root and a package manager; the whole point here
            # is the routes that need neither
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

# _ghr_place_bin <extract-dir> <binary-name> — find the binary and install it.
_ghr_place_bin() {
    local d="$1" bin="$2" found
    found="$(find "$d" -type f -name "$bin" -print 2>/dev/null | head -1)"
    if [[ -z "$found" ]]; then
        # Some releases name the file after the platform (fzf-linux_amd64).
        found="$(find "$d" -maxdepth 2 -type f -perm -u+x -print 2>/dev/null | head -1)"
    fi
    [[ -n "$found" ]] || { log_error "[$NAME] no '$bin' inside the release archive"; return 1; }
    mkdir -p "$ENVUP_LOCAL_BIN"
    install -m 0755 "$found" "$ENVUP_LOCAL_BIN/$bin" 2>/dev/null \
        || { cp -f "$found" "$ENVUP_LOCAL_BIN/$bin" && chmod 0755 "$ENVUP_LOCAL_BIN/$bin"; } \
        || { log_error "[$NAME] could not write $ENVUP_LOCAL_BIN/$bin"; return 1; }
}

# _ghr_place_tree <extract-dir> — for releases that are a whole prefix.
_ghr_place_tree() {
    local d="$1" root sub
    # Archives normally hold a single top directory; use it if so.
    root="$d"
    sub="$(find "$d" -mindepth 1 -maxdepth 1 -print 2>/dev/null)"
    [[ "$(wc -l <<<"$sub")" == 1 && -d "$sub" ]] && root="$sub"

    local dest="$ENVUP_LOCAL_OPT/$NAME"
    mkdir -p "$ENVUP_LOCAL_OPT" "$ENVUP_LOCAL_BIN"
    rm -rf "$dest"
    mv "$root" "$dest" || { log_error "[$NAME] could not install into $dest"; return 1; }

    local f n=0
    for f in "$dest"/bin/*; do
        [[ -f "$f" && -x "$f" ]] || continue
        ln -sf "$f" "$ENVUP_LOCAL_BIN/$(basename "$f")" && n=$((n + 1))
    done
    (( n )) || { log_error "[$NAME] $dest has no bin/ to link"; return 1; }
    log_debug "[$NAME] linked $n binaries from $dest/bin"
}

# ---- the provider --------------------------------------------------------
provider_github_release() {
    local repo="${1:-$GH_REPO}" bin="${GH_BIN:-$VERIFY_BIN}"
    [[ -n "$repo" ]] || { log_error "[$NAME] github_release provider needs GH_REPO"; return 1; }
    [[ -n "$bin" ]]  || { log_error "[$NAME] github_release provider needs GH_BIN or VERIFY_BIN"; return 1; }

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

    local tag=""; tag="$(_ghr_pin "$NAME")" || tag=""
    [[ -n "$tag" ]] && log_info "[$NAME] pinned by versions.lock to $tag"

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

    mkdir -p "$tmp/x"
    _ghr_extract "$file" "$tmp/x"; rc=$?
    if (( rc == 2 )); then                       # a bare binary, not an archive
        chmod +x "$file"; mkdir -p "$tmp/x"; mv "$file" "$tmp/x/$bin"; rc=0
    fi
    if (( rc != 0 )); then
        rm -rf "$tmp"; log_error "[$NAME] could not unpack $(basename "$file")"; return 1
    fi

    if [[ "${GH_TREE:-0}" == 1 ]]; then _ghr_place_tree "$tmp/x"; rc=$?
    else                                _ghr_place_bin  "$tmp/x" "$bin"; rc=$?; fi
    rm -rf "$tmp"
    (( rc == 0 )) || return "$rc"

    # Visible to the verify step in this process even though the shell's PATH
    # was fixed before ~/.local/bin had anything in it.
    export PATH="$ENVUP_LOCAL_BIN:$PATH"
    case ":${PATH_ORIG:-$PATH}:" in
        *":$ENVUP_LOCAL_BIN:"*) ;;
        *) log_once local_bin_path log_warn "$ENVUP_LOCAL_BIN is where envup installs user-space tools — make sure it is on your PATH" ;;
    esac
    log_success "[$NAME] $bin ${_GHR_TAG:+$_GHR_TAG }installed to $ENVUP_LOCAL_BIN"
}
