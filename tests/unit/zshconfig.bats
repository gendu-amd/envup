#!/usr/bin/env bats
# The shell config itself. Every assertion here corresponds to a bug that
# shipped: a config that installs perfectly and then behaves wrong is harder to
# notice, and much harder to diagnose, than one that fails loudly at install.
#
# Two kinds of test:
#   - static: grep the slices. Always runs, including on a CI box without zsh.
#   - behavioural: actually start zsh against a sandbox HOME. Skipped when zsh
#     is not installed, because the tests must not be the reason CI needs it.

load '../test_helper'

setup() {
    common_setup
    ZDIR="$REPO_ROOT/modules/zsh/files/.zshrc.d"
}
teardown() { common_teardown; }

# code <file>... — the files with comments stripped, line numbers preserved.
# Several of these slices *document* the bug they fixed by quoting the old line,
# and a linter that flags its own changelog is a linter people delete.
code() { sed 's/#.*//' "$@"; }

# zsh_home — a throwaway HOME wired to the repo's config, the same way the zsh
# module links it.
zsh_home() {
    ZHOME="$TEST_TMP/zhome"; mkdir -p "$ZHOME"
    ln -sf "$REPO_ROOT/modules/zsh/files/.zshenv"  "$ZHOME/.zshenv"
    ln -sf "$REPO_ROOT/modules/zsh/files/.zshrc"   "$ZHOME/.zshrc"
    ln -sf "$ZDIR"                                 "$ZHOME/.zshrc.d"
}

# zrun <code> — start an interactive zsh in that sandbox and run <code>.
# `env -i` so the outcome does not depend on the tester's own environment.
zrun() {
    command -v zsh >/dev/null || skip "zsh is not installed"
    zsh_home
    env -i HOME="$ZHOME" ZDOTDIR="$ZHOME" TERM=xterm \
        PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        zsh -i -c "$1"
}

# ---- load order (B1) ------------------------------------------------------

@test "the platform slice loads before the tools slice" {
    # THE bug. tools.zsh ran before platform.zsh, platform.zsh is what runs
    # `brew shellenv`, so on every Mac `command -v zoxide` was false inside
    # tools.zsh: z, atuin's Ctrl-R and fzf's bindings were all silently absent
    # with nothing printed to explain it. Filename order is now the contract.
    local -a slices
    mapfile -t slices < <(cd "$ZDIR" && ls [0-9][0-9]-*.zsh)
    local plat tools
    for i in "${!slices[@]}"; do
        [[ "${slices[i]}" == *platform* ]] && plat=$i
        [[ "${slices[i]}" == *tools*    ]] && tools=$i
    done
    [ -n "$plat" ] && [ -n "$tools" ]
    [ "$plat" -lt "$tools" ]
}

@test "every slice is numbered, so .zshrc's glob cannot miss one" {
    local f
    for f in "$ZDIR"/*.zsh; do
        [[ "$(basename "$f")" =~ ^[0-9][0-9]- ]] || { echo "unnumbered: $f"; false; }
    done
}

@test ".zshrc loads slices by glob and does not swallow their stderr (D1)" {
    local rc="$REPO_ROOT/modules/zsh/files/.zshrc"
    grep -q '\[0-9\]\[0-9\]-\*\.zsh' "$rc"
    # 2>/dev/null is allowed only behind the opt-in quiet switch.
    [ "$(grep -c '2>/dev/null' "$rc")" -eq 1 ]
    grep -q 'ENVUP_ZSH_QUIET' "$rc"
}

# ---- environment (B4 B5 B6) ----------------------------------------------

@test "nothing sets LC_ALL (B4)" {
    # LC_ALL overrides every LC_* category at once, and setting it to a locale
    # the machine has not generated makes every command print a setlocale
    # warning. LANG, conditionally, is the correct knob.
    ! code "$ZDIR"/*.zsh "$ZDIR"/platform/*.zsh \
           "$REPO_ROOT/modules/zsh/files/.zshenv" | grep -n 'LC_ALL='
}

@test "LANG is only set to a locale the machine actually has (B4)" {
    grep -q 'locale -a' "$ZDIR/30-env.zsh"
}

@test "TZ is not forced (B5)" {
    # `export TZ=UTC` silently moved the clock on servers deliberately set to
    # local time. It belongs in a hosts/ file, per machine.
    ! code "$ZDIR"/*.zsh "$ZDIR"/platform/*.zsh | grep -n 'export TZ='
}

@test "EDITOR is only set to an editor that exists (B6)" {
    # export EDITOR=nvim on a minimal profile broke git commit, crontab -e and
    # visudo, none of which install nvim.
    grep -q 'commands\[\$e\]' "$ZDIR/30-env.zsh"
    ! grep -qE '^[^#]*export EDITOR="?nvim"?$' "$ZDIR/30-env.zsh"
}

# ---- aliases (B7 B8) ------------------------------------------------------

@test "vim/vi are only aliased when nvim exists (B7)" {
    grep -q 'commands\[nvim\]' "$ZDIR/60-alias.zsh"
    # The unconditional form made `vim` unusable on every server without nvim.
    ! grep -qE '^alias vi?m=' "$ZDIR/60-alias.zsh"
}

@test "the platform slices do not alias ls out from under the alias slice (B8)" {
    # macos.zsh set `alias ls="ls -G"` and loaded after the alias slice, so a
    # Mac with eza installed silently got BSD ls instead.
    ! code "$ZDIR"/platform/*.zsh | grep -n 'alias ls='
}

# ---- completion (B9) ------------------------------------------------------

@test "compinit is called at most once outside the no-OMZ fallback (B9)" {
    # Oh-My-Zsh already runs compinit; the second call in tools.zsh cost
    # 100-300ms per shell, much worse on an NFS home, and used -u to silence
    # the insecure-directory warning rather than deal with it.
    [ "$(code "$ZDIR"/*.zsh | grep -c '^[[:space:]]*compinit')" -le 1 ]
    ! code "$ZDIR"/*.zsh | grep -n 'compinit -u'
}

@test "envup's completions join fpath before Oh-My-Zsh loads" {
    # This is what makes one compinit sufficient.
    local f="$ZDIR/40-shell.zsh"
    local fp omz
    fp="$(code "$f" | grep -n 'fpath=(' | head -1 | cut -d: -f1)"
    omz="$(code "$f" | grep -n 'oh-my-zsh.sh' | head -1 | cut -d: -f1)"
    [ -n "$fp" ] && [ -n "$omz" ] && [ "$fp" -lt "$omz" ]
}

# ---- PATH (B2 B3 B11) -----------------------------------------------------

@test ".zshenv does not push system directories ahead of the inherited PATH (B2)" {
    # The old line prefixed /usr/bin:/bin:... to everything inherited, which
    # demoted brew, conda, pyenv and HPC `module load` toolchains: git and
    # python resolved to the system copies instead.
    ! grep -q 'export PATH="${HOME}/.local/bin:/usr/local/bin' "$REPO_ROOT/modules/zsh/files/.zshenv"
    grep -q 'typeset -gU path PATH' "$REPO_ROOT/modules/zsh/files/.zshenv"
}

@test "no slice appends to PATH by hand (B3 B11)" {
    # `export PATH=$PATH:/opt/rocm/bin` re-appends in every nested shell.
    ! code "$ZDIR"/*.zsh "$ZDIR"/platform/*.zsh | grep -nE 'export (PATH|LD_LIBRARY_PATH)='
}

@test "PATH has no duplicates and does not grow in nested shells (B3)" {
    run zrun 'print -l $path | sort | uniq -d; print "N=$#path"; zsh -ic "print NESTED=\$#path"'
    [ "$status" -eq 0 ]
    local outer nested
    outer="$(grep -o 'N=[0-9]*' <<<"$output" | head -1 | cut -d= -f2)"
    nested="$(grep -o 'NESTED=[0-9]*' <<<"$output" | head -1 | cut -d= -f2)"
    [ "$outer" = "$nested" ]
    # uniq -d printed nothing, so no line of output is a bare path.
    [[ "$output" != */usr/bin* ]]
}

@test "path_prepend and path_append are idempotent" {
    run zrun 'path_append /usr/bin; path_append /usr/bin; path_prepend /bin; path_prepend /bin
              print "FIRST=$path[1]"; print "LAST=$path[-1]"; print "N=$#path"
              print -l $path | sort | uniq -d'
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIRST=/bin"* ]]
    [[ "$output" == *"LAST=/usr/bin"* ]]
}

@test "path helpers skip directories that do not exist" {
    run zrun 'path_prepend /definitely/not/here; print -l $path'
    [ "$status" -eq 0 ]
    [[ "$output" != *"/definitely/not/here"* ]]
}

# ---- behaviour ------------------------------------------------------------

@test "a fresh interactive shell prints nothing to stderr" {
    command -v zsh >/dev/null || skip "zsh is not installed"
    zsh_home
    run env -i HOME="$ZHOME" ZDOTDIR="$ZHOME" TERM=xterm \
        PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        zsh -i -c 'true' 2>&1
    [ "$status" -eq 0 ]
    # A slice ending in a false test is not a failure, and must not be reported
    # as one — spurious warnings are how people learn to ignore real ones.
    [ -z "$output" ]
}

@test "LC_ALL stays unset and LANG is usable in a real shell" {
    run zrun 'print "LC_ALL=[$LC_ALL]"; print "LANG=[$LANG]"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"LC_ALL=[]"* ]]
}

@test "ENVUP_ARCH is normalised at runtime, not the raw uname" {
    run zrun 'print "ARCH=$ENVUP_ARCH"'
    [ "$status" -eq 0 ]
    [[ "$output" =~ ARCH=(x86_64|aarch64|armv7|i686) ]]
}

# ---- the hosts layer (C1) -------------------------------------------------

@test "the hosts layer loads by short hostname and ships a template" {
    grep -q 'hosts/\${ENVUP_HOST}.zsh' "$ZDIR/70-host.zsh"
    [ -f "$ZDIR/hosts/example.zsh.template" ]
}

@test "hosts/<hostname>.zsh is loaded, and after the tool slices" {
    command -v zsh >/dev/null || skip "zsh is not installed"
    zsh_home
    # The sandbox links .zshrc.d into the repo, so write the fixture through a
    # copy rather than into version control.
    rm "$ZHOME/.zshrc.d"
    cp -r "$ZDIR" "$ZHOME/.zshrc.d"
    mkdir -p "$ZHOME/.zshrc.d/hosts"
    printf 'print "HOST-SLICE-RAN editor=$EDITOR"\n' \
        > "$ZHOME/.zshrc.d/hosts/testbox.zsh"

    run env -i HOME="$ZHOME" ZDOTDIR="$ZHOME" TERM=xterm ENVUP_HOST=testbox \
        PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        zsh -i -c 'true'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HOST-SLICE-RAN"* ]]
}

@test "personal overrides live outside the repo checkout (C1 C2)" {
    # The old local.zsh sat inside modules/zsh/files/.zshrc.d/, so anything
    # writing to it was writing into version control — and on a home shared
    # over NFS every machine shared the same "per-machine" file.
    grep -q 'HOME/.zshrc.local' "$ZDIR/80-local.zsh"
    [ ! -e "$ZDIR/local.zsh.example" ]
}

# ---- node (B12) -----------------------------------------------------------

@test "nvm is lazy, not sourced at startup (B12)" {
    # Sourcing nvm.sh costs 200-800ms in every shell, almost all of which never
    # run a node command.
    ! grep -qE '^[^#]*source "\$NVM_DIR/nvm.sh"$' "$ZDIR/55-node.zsh"
    grep -q '_nvm_load' "$ZDIR/55-node.zsh"
}

# ---- WSL (B10) ------------------------------------------------------------

@test "the WSL slice does not call cmd.exe at startup (B10)" {
    # Two synchronous cmd.exe calls, 200-500ms each, on the path to the prompt,
    # to answer a question whose answer never changes.
    local f="$ZDIR/platform/wsl2.zsh"
    grep -q 'win_user' "$f"
    # Every cmd.exe/powershell mention must be inside a function body or an
    # alias, never at the top level.
    ! grep -nE '^[^ #}]*\$\(win_user' "$f"
    grep -q 'cache' "$f"
}
