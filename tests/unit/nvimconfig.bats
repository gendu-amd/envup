#!/usr/bin/env bats
# The nvim config, checked as text.
#
# Nothing here runs neovim: the whole point of this repo is machines where the
# editor may not be installed, or is installed and cannot start (the prebuilt
# 0.11 AppImage wants glibc 2.33, and half the servers this targets do not have
# it). So these assert on the source — which is enough, because every one of
# them guards a decision that is easy to undo by accident and silent when it
# goes wrong.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

NV()      { printf '%s' "$REPO_ROOT/modules/nvim/files/$1"; }
OPTIONS() { NV lua/options.lua; }
CONFORM() { NV lua/configs/conform.lua; }
BIGFILE() { NV lua/configs/bigfile.lua; }
LSPCFG()  { NV lua/configs/lspconfig.lua; }
PLUGINS() { NV lua/plugins/init.lua; }
INIT()    { NV init.lua; }

lua_bin() {
    command -v luajit 2>/dev/null || command -v lua5.1 2>/dev/null || command -v lua 2>/dev/null
}

@test "every lua file added here parses" {
    local lua; lua="$(lua_bin)" || skip "no lua interpreter"
    [[ -n "$lua" ]] || skip "no lua interpreter"
    local f
    for f in "$(OPTIONS)" "$(CONFORM)" "$(BIGFILE)" "$(LSPCFG)" "$(PLUGINS)" "$(INIT)"; do
        run "$lua" -e "assert(loadfile('$f'))"
        [ "$status" -eq 0 ] || { echo "$f: $output"; return 1; }
    done
}

# ---- undo that outlives the session --------------------------------------

@test "undo history is written to disk" {
    # An SSH connection drops, the shell dies, nvim dies with it. Without
    # undofile everything before the last write is unrecoverable — which is a
    # strange thing to accept on the machines this config is aimed at.
    grep -Eq '^o\.undofile = true' "$(OPTIONS)"
}

@test "the undo limit is raised to match" {
    # Persisting 1000 levels of undo is barely worth the file.
    grep -Eq '^o\.undolevels = [0-9]{4,}' "$(OPTIONS)"
}

@test "no undodir is hard-coded" {
    # stdpath("state") already differs per machine and per user; naming a
    # directory here is how a home shared over NFS ends up with two machines
    # writing the same undo file.
    ! grep -q 'undodir' "$(OPTIONS)"
}

# ---- big files -----------------------------------------------------------

@test "a big file opens with syntax, LSP and undo switched off" {
    grep -q 'undofile = false'  "$(BIGFILE)"
    grep -q 'swapfile = false'  "$(BIGFILE)"
    grep -q 'syntax\] *= *"off"\|syntax = "off"' "$(BIGFILE)"
    grep -q 'buf_detach_client' "$(BIGFILE)"
}

@test "the size decision is made before the file is read" {
    # BufReadPost is too late for 'syntax': the highlighter has already started
    # on a 200 MB buffer by then, which is the hang this exists to prevent.
    grep -q 'BufReadPre' "$(BIGFILE)"
}

@test "treesitter is stopped as well as syntax" {
    # Two separate highlighters. Turning off 'syntax' and leaving treesitter
    # parsing is the version of this feature that does not work.
    grep -q 'treesitter.stop' "$(BIGFILE)"
}

@test "the threshold is overridable, and 0 turns it off" {
    grep -q 'vim.g.envup_bigfile_bytes' "$(BIGFILE)"
    grep -q 'max <= 0' "$(BIGFILE)"
}

@test "you are told why the buffer behaves differently" {
    # Otherwise the file just silently has no colours and no jump-to-definition,
    # and you spend ten minutes deciding the LSP is broken.
    grep -q 'vim.notify' "$(BIGFILE)"
}

@test "init.lua actually arms the big-file guard" {
    grep -q 'require("configs.bigfile").setup()' "$(INIT)"
}

# ---- formatting ----------------------------------------------------------

@test "format on save is refused unless the project ships its style config" {
    # clang-format with no .clang-format reflows the file to LLVM style. Turned
    # on unconditionally, your first save in someone else's repository produces
    # a diff of the entire file that you then have to explain.
    grep -q 'project_has_style' "$(CONFORM)"
    grep -q "'%.clang%-format'\|\.clang-format" "$(CONFORM)"
}

@test "the style search walks up to the project root" {
    # A .clang-format sits at the top of a repo; the file you are editing is
    # six directories down.
    grep -q 'upward = true' "$(CONFORM)"
}

@test "format on save can be turned off per buffer and per session" {
    grep -q 'vim.b\[bufnr\].disable_autoformat' "$(CONFORM)"
    grep -q 'vim.g.disable_autoformat' "$(CONFORM)"
}

@test "and forced on for people who want it everywhere" {
    grep -q 'vim.g.envup_format_always' "$(CONFORM)"
}

@test "a big file is never reformatted on save" {
    # Same buffer flag the big-file guard sets. Running a formatter over 200 MB
    # would undo the entire point of opening it in a stripped-down buffer.
    grep -q 'envup_bigfile' "$(CONFORM)"
}

@test "the LSP is not used as a formatting fallback" {
    # An LSP that formats on save is exactly the surprise project_has_style
    # exists to prevent, arriving from a different binary.
    grep -q 'lsp_format = "never"' "$(CONFORM)"
}

@test "python tries ruff and stops there if it worked" {
    # Without stop_after_first both ruff and black run, in that order, and the
    # file ends up in whichever style black has.
    grep -q 'stop_after_first = true' "$(CONFORM)"
}

@test "shfmt is told to match the editor's indentation" {
    # Its default is tabs, so a formatted script stops looking like the
    # unformatted one next to it.
    grep -q 'shfmt = { prepend_args' "$(CONFORM)"
}

@test "conform is loaded before the first save, not after it" {
    # opts alone is not enough: lazy.nvim would load conform on some later
    # event and format_on_save would simply never be consulted.
    grep -q 'event = "BufWritePre"' "$(PLUGINS)"
}

@test "ConformInfo is reachable" {
    # It is the only way to find out why a formatter did nothing.
    grep -q 'cmd = "ConformInfo"' "$(PLUGINS)"
}

# ---- diagnostics ---------------------------------------------------------

@test "the full diagnostic text is one keystroke away" {
    # Virtual text is truncated at the screen edge, and a clangd template error
    # does not fit on a line. The float is where you actually read it.
    grep -q 'open_float' "$(LSPCFG)"
}

@test "moving between problems is bound to the vim motions" {
    grep -q '"\]d"' "$(LSPCFG)"
    grep -q '"\[d"' "$(LSPCFG)"
}

@test "the float key does not shadow NvChad's <leader>ds" {
    # A bare <leader>d would be a prefix of <leader>ds, so every use of either
    # waits out timeoutlen first.
    grep -q '<leader>df' "$(LSPCFG)"
    ! grep -Eq '"<leader>d"' "$(LSPCFG)"
}

@test "diagnostics do not appear while you are still typing" {
    grep -q 'update_in_insert = false' "$(LSPCFG)"
}

@test "both the 0.10 and the 0.11 jump APIs are handled" {
    # vim.diagnostic.jump arrived in 0.11 and deprecates goto_next/goto_prev.
    # This config still runs on 0.10 — see the NvChad commit pin — so picking
    # one of the two would break half the machines.
    grep -q 'vim.diagnostic.jump' "$(LSPCFG)"
    grep -q 'goto_next' "$(LSPCFG)"
    grep -q 'goto_prev' "$(LSPCFG)"
}
