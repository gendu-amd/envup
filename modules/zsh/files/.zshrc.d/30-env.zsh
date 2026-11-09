# ============================================
# 30 — environment
# ============================================
# Everything here used to be unconditional, and every one of them broke a real
# machine:
#
#   export LC_ALL=en_US.UTF-8   on a server with no generated locales, this
#                               makes every single command print a setlocale
#                               warning. LC_ALL also overrides all LC_* at once,
#                               so it is the wrong variable even when the locale
#                               does exist.
#   export TZ=UTC               silently changed the clock on servers that were
#                               deliberately set to local time.
#   export EDITOR=nvim          the minimal and standard profiles do not install
#                               nvim, so `git commit`, `crontab -e` and `visudo`
#                               all failed with "editor not found".
#
# The rule for this slice: set nothing you have not checked exists.

# ---- locale ---------------------------------------------------------------
# Only LANG, only if what we would set is actually generated, and only if the
# inherited LANG isn't already UTF-8.
if [[ -z "${LANG:-}" || "${LANG:l}" != *utf*8* ]]; then
    () {
        local -a have
        local want
        have=(${(f)"$(locale -a 2>/dev/null)"})
        # locale -a prints en_US.utf8; the name people write is en_US.UTF-8.
        have=(${have:l})
        have=(${have//-/})
        for want in en_US.UTF-8 C.UTF-8; do
            if (( ${have[(I)${${want:l}//-/}]} )); then
                export LANG="$want"
                break
            fi
        done
    }
fi

# ---- timezone -------------------------------------------------------------
# Deliberately not set. A server's clock is the admin's decision; if you want
# UTC on a particular machine, put `export TZ=UTC` in its hosts/ file.

# ---- editor ---------------------------------------------------------------
() {
    local e
    for e in "${ENVUP_EDITOR:-}" nvim vim vi nano; do
        [[ -n "$e" ]] && (( $+commands[$e] )) && { export EDITOR="$e" VISUAL="$e"; return; }
    done
}

# ---- workspace ------------------------------------------------------------
# Containers mount the real work somewhere that isn't $HOME. Only meaningful
# in a container, and the platform verdict already told us whether we are in
# one — this used to be a third, independent docker check.
if [[ "$ENVUP_PLATFORM" == docker ]]; then
    () {
        local d
        for d in /workspace /mnt/workspace /mnt/host; do
            [[ -d "$d" ]] && { export WORKSPACE="$d"; return; }
        done
    }
fi

# ---- misc -----------------------------------------------------------------
export LESS="${LESS:--R}"
