#!/usr/bin/env bats
# Copy on a server -> clipboard of the machine you are sitting at, over OSC 52.
#
# Every assertion here corresponds to something that fails *silently*. tmux's
# default set-clipboard swallows the sequence, a terminfo without Ms makes tmux
# emit nothing at all, and nvim's built-in OSC 52 reader waits ten seconds for a
# reply no terminal will send. None of those announce themselves; they just look
# like "copy doesn't work". So they get tests.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

TMUX_CONF() { printf '%s' "$REPO_ROOT/modules/tmux/files/.tmux.conf"; }
CLIP_LUA()  { printf '%s' "$REPO_ROOT/modules/nvim/files/lua/configs/clipboard.lua"; }

@test "tmux accepts OSC 52 from applications, not just from itself" {
    # 'external' — the default — sends tmux's own copies onward but drops
    # sequences arriving from an application, so a yank in nvim goes nowhere.
    grep -Eq '^set -s set-clipboard on' "$(TMUX_CONF)"
}

@test "tmux is given the Ms capability, or it emits nothing at all" {
    # tmux >= 2.6 refuses to send OSC 52 unless terminfo advertises Ms, and
    # hardly any terminfo entry does. tmux ships an override for xterm* only.
    grep -q 'terminal-overrides.*Ms=' "$(TMUX_CONF)"
}

@test "the Ms override covers more than xterm" {
    # screen*/tmux* is what you get inside tmux, and a locked-down box reports
    # whatever it reports. A terminal that does not understand OSC 52 ignores
    # the sequence, so the wildcard costs nothing.
    grep -q "terminal-overrides ',\*:Ms=" "$(TMUX_CONF)"
}

@test "the Ms escape survives tmux's own string parsing" {
    # Written in double quotes, tmux eats the backslashes and stores a literal
    # 'E]52;...7' that no terminal recognises — and says nothing about it.
    local line; line="$(grep 'Ms=' "$(TMUX_CONF)")"
    [[ "$line" == *"'"*"\\E]52;%p1%s;%p2%s\\007"*"'"* ]]
}

@test "the Ms override appends, so tmux's own xterm entry survives" {
    grep -q 'set -ga terminal-overrides' "$(TMUX_CONF)"
}

@test "copy-mode y reaches the clipboard rather than only tmux's buffer" {
    grep -q 'copy-mode-vi y send -X copy-selection-and-cancel' "$(TMUX_CONF)"
}

@test "the tmux clipboard config is valid tmux syntax" {
    command -v tmux >/dev/null 2>&1 || skip "tmux not installed"
    local sock="envup-clip-$$"
    run tmux -L "$sock" -f "$(TMUX_CONF)" start-server \; \
        show -s set-clipboard \; kill-server
    tmux -L "$sock" kill-server 2>/dev/null || true
    [ "$status" -eq 0 ]
    [[ "$output" == *"set-clipboard on"* ]]
}

# ---- nvim ----------------------------------------------------------------

@test "clipboard.lua is valid lua" {
    command -v luajit >/dev/null 2>&1 || command -v lua5.1 >/dev/null 2>&1 ||
        command -v lua >/dev/null 2>&1 || skip "no lua interpreter"
    local lua; lua="$(command -v luajit || command -v lua5.1 || command -v lua)"
    run "$lua" -e "assert(loadfile('$(CLIP_LUA)'))"
    [ "$status" -eq 0 ]
}

@test "nvim's paste does not query the terminal" {
    # osc52.paste() asks the terminal for its clipboard and blocks for the full
    # timeout when nothing answers — which is every terminal the team uses, all
    # of which implement write and deliberately refuse read. Ten seconds per
    # 'p'. The provider returns the unnamed register instead.
    ! grep -q 'osc52\.paste' "$(CLIP_LUA)"
    grep -q "getreg('\"')" "$(CLIP_LUA)"
}

@test "nvim yields to a real clipboard tool when the machine has one" {
    # A native provider can paste as well as copy, so taking over on a desktop
    # would be a downgrade.
    local f; f="$(CLIP_LUA)"
    grep -q 'has_native_clipboard' "$f"
    grep -q 'pbcopy'   "$f"      # macOS
    grep -q 'clip.exe' "$f"      # WSL
    grep -q 'wl-copy'  "$f"      # Wayland
    grep -q 'xclip'    "$f"      # X11
    # The exit is early and unconditional: if a tool is there, do nothing.
    grep -q 'if has_native_clipboard() then return end' "$f"
}

@test "a clipboard tool only counts when it can actually reach a display" {
    # xclip on a headless server is on PATH and prints an error. Requiring the
    # matching display variable is the difference between a clipboard and a
    # confusing failure.
    local f; f="$(CLIP_LUA)"
    grep -q 'WAYLAND_DISPLAY' "$f"
    grep -q 'vim.env.DISPLAY' "$f"
}

@test "an old nvim degrades quietly instead of erroring on startup" {
    # vim.ui.clipboard.osc52 arrived in 0.10; the pinned ceiling means some
    # machines are below it. A hard require would break every startup there.
    grep -q 'pcall(require, "vim.ui.clipboard.osc52")' "$(CLIP_LUA)"
    grep -q 'if not ok then return end' "$(CLIP_LUA)"
}

@test "an oversized copy is refused out loud" {
    # Terminals drop an escape sequence past their limit without a word, which
    # is indistinguishable from "the clipboard didn't update".
    local f; f="$(CLIP_LUA)"
    grep -q 'LIMIT = 64 \* 1024' "$f"
    grep -q 'vim.notify' "$f"
}

@test "the clipboard decision is made after NvChad sets clipboard=unnamedplus" {
    # options.lua is where unnamedplus is set; deciding before it would be
    # decided about nothing.
    local init="$REPO_ROOT/modules/nvim/files/init.lua"
    local opts_at clip_at
    opts_at="$(grep -n 'require "options"' "$init" | cut -d: -f1)"
    clip_at="$(grep -n 'require "configs.clipboard"' "$init" | cut -d: -f1)"
    [[ -n "$opts_at" && -n "$clip_at" ]]
    (( opts_at < clip_at ))
}

@test "a host file can still overrule the whole clipboard decision" {
    grep -q 'vim.g.clipboard' "$REPO_ROOT/modules/nvim/files/hosts/example.lua.template"
}

@test "the terminal-side setup is documented, because envup cannot do it" {
    # VS Code / Cursor ships OSC 52 write turned OFF. Without this one setting
    # every copy silently does nothing, and no amount of server-side config
    # helps. It has to be written down somewhere.
    local d="$REPO_ROOT/docs/CLIPBOARD.md"
    [ -f "$d" ]
    grep -q 'enableClipboardWrite' "$d"
}
