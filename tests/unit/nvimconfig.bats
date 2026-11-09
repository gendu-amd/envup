#!/usr/bin/env bats
# Static checks for Nvim behavior; runtime coverage lives in acceptance checks.

load '../test_helper'

setup() { common_setup; }
teardown() { common_teardown; }

NV()      { printf '%s' "$REPO_ROOT/modules/nvim/files/$1"; }
OPTIONS() { NV lua/options.lua; }
CONFORM() { NV lua/configs/conform.lua; }
TOOLS()   { NV lua/configs/tools.lua; }
BIGFILE() { NV lua/configs/bigfile.lua; }
LSPCFG()  { NV lua/configs/lspconfig.lua; }
PLUGINS() { NV lua/plugins/init.lua; }
MAPPINGS() { NV lua/mappings.lua; }
INIT()    { NV init.lua; }

lua_bin() {
    command -v luajit 2>/dev/null || command -v lua5.1 2>/dev/null || command -v lua 2>/dev/null
}

nvim_runtime_fixture() {
    NVIM_REAL="$(command -v nvim)" || skip "nvim not installed"
    version_ge "$(bin_version nvim)" 0.10 || skip "requires nvim >= 0.10"
    export XDG_CONFIG_HOME="$TEST_TMP/config" XDG_DATA_HOME="$TEST_TMP/data"
    export XDG_STATE_HOME="$TEST_TMP/nvim-state" XDG_CACHE_HOME="$TEST_TMP/cache"
    export NVIM_APPNAME=nvim NVIM_LOG_FILE=/dev/null
    unset ENVUP_NVIM_LAZY
    mkdir -p "$XDG_CONFIG_HOME/nvim/lua/configs" "$ENVUP_HOME/modules/nvim/files/lua/configs"
    cp "$(TOOLS)" "$XDG_CONFIG_HOME/nvim/lua/configs/tools.lua"
    cp "$(NV lua/configs/clipboard.lua)" "$XDG_CONFIG_HOME/nvim/lua/configs/clipboard.lua"
    cp "$(TOOLS)" "$ENVUP_HOME/modules/nvim/files/lua/configs/tools.lua"
    cp "$(NV lua/configs/clipboard.lua)" "$ENVUP_HOME/modules/nvim/files/lua/configs/clipboard.lua"
    cp "$(INIT)" "$XDG_CONFIG_HOME/nvim/init.lua"
    cp "$(NV lazy-lock.json)" "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
    source "$REPO_ROOT/modules/nvim/meta.sh"
    source "$REPO_ROOT/modules/nvim/hooks.sh"
    stub_bin git <<'EOF'
#!/bin/bash
touch "$HOME/network-ran"
exit 1
EOF
}

session_fixture() {
    nvim_runtime_fixture
    export TMUX=envup-test-session NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    mkdir -p "$TEST_TMP/project"
    printf '%s\n' '-- fixture' > "$TEST_TMP/project/sample.lua"
    cd "$TEST_TMP/project"
}

@test "Nvim session save and exit preserve an existing user Session.vim" {
    session_fixture
    printf '%s\n' '" user-created session' > Session.vim
    cat > "$TEST_TMP/session.lua" <<'EOF'
local session = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/session.lua")
session.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
session.save()
assert(vim.fn.readfile("Session.vim")[1] == '" user-created session')
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n sample.lua \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/session.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ "$(cat Session.vim)" = '" user-created session' ]
}

@test "Nvim cleans only its own unchanged session files across directory changes" {
    session_fixture
    mkdir second
    cat > "$TEST_TMP/session.lua" <<'EOF'
local session = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/session.lua")
session.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
session.save()
assert(vim.fn.readfile("Session.vim")[1]:find('" envup tmux session: ', 1, true) == 1)
session.save()
vim.cmd("cd second")
session.save()
assert(vim.fn.filereadable("Session.vim") == 1)
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n sample.lua \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/session.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e Session.vim ]
    [ ! -e second/Session.vim ]
}

@test "Nvim preserves edits to an envup session instead of overwriting or deleting them" {
    session_fixture
    cat > "$TEST_TMP/session.lua" <<'EOF'
local session = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/session.lua")
session.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
session.save()
local edited = vim.fn.readfile("Session.vim")
table.insert(edited, '" user edit')
vim.fn.writefile(edited, "Session.vim")
session.save()
assert(vim.deep_equal(vim.fn.readfile("Session.vim"), edited))
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n sample.lua \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/session.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    run tail -1 Session.vim
    [ "$output" = '" user edit' ]
}

@test "Nvim session recovery accepts marked files and preserves replacement symlinks" {
    session_fixture
    cat > "$TEST_TMP/session.lua" <<'EOF'
local body = { '" old generated session' }
vim.fn.writefile({ '" envup tmux session: 1 ' .. vim.fn.sha256(table.concat(body, "\n")), body[1] }, "Session.vim")
local session = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/session.lua")
session.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
session.save()
local marker = vim.fn.readfile("Session.vim")[1]
assert(marker:find('" envup tmux session: ' .. vim.uv.os_getpid() .. " ", 1, true) == 1)
assert(vim.uv.fs_rename("Session.vim", "user-session.vim"))
assert(vim.uv.fs_symlink("user-session.vim", "Session.vim"))
session.save()
assert(vim.uv.fs_lstat("Session.vim").type == "link")
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n sample.lua \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/session.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ -L Session.vim ]
    [ -f user-session.vim ]
}

@test "Nvim preserves edits to a marked session left by an earlier process" {
    session_fixture
    cat > "$TEST_TMP/session.lua" <<'EOF'
local body = { '" old generated session' }
local edited = { '" envup tmux session: 1 ' .. vim.fn.sha256(table.concat(body, "\n")), body[1], '" user edit' }
vim.fn.writefile(edited, "Session.vim")
local session = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/session.lua")
session.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
session.save()
assert(vim.deep_equal(vim.fn.readfile("Session.vim"), edited))
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n sample.lua \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/session.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    run tail -1 Session.vim
    [ "$output" = '" user edit' ]
}

@test "Lazy writes and interrupted updates cannot change the shared pinned lock" {
    nvim_runtime_fixture
    cp "$XDG_CONFIG_HOME/nvim/lazy-lock.json" "$TEST_TMP/pinned-lock.json"
    rm "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
    ln -s "$TEST_TMP/pinned-lock.json" "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
    cat > "$TEST_TMP/lock.lua" <<'EOF'
local tools = require "configs.tools"
local source = vim.fn.stdpath "config" .. "/lazy-lock.json"
local original = vim.fn.readfile(source)
local config = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lazy.lua")
assert(config.lockfile == vim.fn.stdpath "state" .. "/lazy-lock.json")
assert(vim.deep_equal(vim.fn.readfile(config.lockfile), original))
vim.fn.writefile({ "{" }, config.lockfile)
assert(vim.deep_equal(vim.fn.readfile(source), original))
assert(tools.prepare_lock() == config.lockfile)
assert(vim.deep_equal(vim.fn.readfile(config.lockfile), original))
vim.fn.writefile({ '{}' }, config.lockfile)
tools.prepare_lock()
assert(vim.fn.readfile(config.lockfile)[1] == '{}')
tools.prepare_lock(true)
assert(vim.deep_equal(vim.fn.readfile(config.lockfile), original))
vim.uv.fs_unlink(config.lockfile)
assert(vim.uv.fs_symlink(source, config.lockfile))
local ok, err = pcall(tools.prepare_lock, true)
assert(not ok and tostring(err):find("regular file", 1, true))
assert(vim.deep_equal(vim.fn.readfile(source), original))
EOF
    export NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/lock.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
}

@test "WSL clip.exe copies through the real Nvim provider and pastes the local register" {
    nvim_runtime_fixture
    unset DISPLAY WAYLAND_DISPLAY
    stub_bin clip.exe <<'EOF'
#!/bin/bash
cat > "$HOME/copied.txt"
EOF
    cat > "$TEST_TMP/clipboard.lua" <<'EOF'
dofile(vim.fn.stdpath "config" .. "/lua/configs/clipboard.lua")
assert(vim.g.clipboard.name == "WSL clip.exe (copy only)")
vim.o.clipboard = "unnamedplus"
vim.fn.setreg('"', "local paste")
assert(vim.deep_equal(vim.g.clipboard.paste["+"](), { { "local paste" }, "v" }))
assert(vim.fn.getreg("+") == "local paste")
vim.fn.setreg("+", { "WSL copy", "second line" }, "V")
assert(vim.wait(3000, function()
  local path = vim.env.HOME .. "/copied.txt"
  return vim.fn.filereadable(path) == 1 and vim.deep_equal(vim.fn.readfile(path), { "WSL copy", "second line" })
end))
assert(vim.deep_equal(vim.fn.readfile(vim.env.HOME .. "/copied.txt"), { "WSL copy", "second line" }))
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/clipboard.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
}

@test "copy-only OSC52 and WSL preserve character, line and block paste semantics" {
    nvim_runtime_fixture
    unset DISPLAY WAYLAND_DISPLAY
    cat > "$TEST_TMP/registers.lua" <<'EOF'
dofile(vim.fn.stdpath "config" .. "/lua/configs/clipboard.lua")
assert(vim.g.clipboard.name == vim.env.EXPECTED_PROVIDER)
for _, case in ipairs({
  { { "alpha", "beta" }, "v" },
  { { "alpha", "beta" }, "V" },
  { { "ab", "cd" }, string.char(22) .. "2" },
  { { "alpha", "", "beta" }, "v" },
}) do
  for _, reg in ipairs({ "+", "*" }) do
    local initial = { "123456", "ABCDEF", "abcdef" }
    vim.api.nvim_buf_set_lines(0, 0, -1, false, initial)
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    vim.fn.setreg("a", case[1], case[2])
    vim.cmd('normal! "ap')
    local expected = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, initial)
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    vim.fn.setreg('"', case[1], case[2])
    assert(vim.deep_equal(vim.fn.getreg(reg, 1, true), case[1]))
    assert(vim.fn.getregtype(reg) == case[2])
    vim.cmd('normal! "' .. reg .. 'p')
    assert(vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), expected))
  end
end
EOF
    EXPECTED_PROVIDER='OSC 52' run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/registers.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa!
    [ "$status" -eq 0 ]
    stub_bin clip.exe <<'EOF'
#!/bin/bash
cat > "$HOME/copied.txt"
EOF
    EXPECTED_PROVIDER='WSL clip.exe (copy only)' run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/registers.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa!
    [ "$status" -eq 0 ]
}

@test "clangd chooses the nearest project marker before a parent workspace config" {
    nvim_runtime_fixture
    printf '{"languages":["cpp"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    mkdir -p "$TEST_TMP/workspace/project"
    touch "$TEST_TMP/workspace/.clangd" "$TEST_TMP/workspace/project/compile_commands.json"
    export NVIM_SOURCE="$REPO_ROOT/modules/nvim/files" PROJECT_ROOT="$TEST_TMP/workspace/project"
    cat > "$TEST_TMP/root.lua" <<'EOF'
package.loaded["nvchad.configs.lspconfig"] = {}
local configured
package.loaded.lspconfig = { clangd = { setup = function(opts) configured = opts end } }
dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lspconfig.lua")
assert(configured.root_dir(vim.env.PROJECT_ROOT .. "/main.cpp") == vim.env.PROJECT_ROOT)
assert(configured.root_dir(vim.env.PROJECT_ROOT .. "/../outside.cpp") == vim.fs.dirname(vim.env.PROJECT_ROOT))
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/root.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
}

@test "copy-only Wayland falls back to OSC52 and core or cold-cache startup keeps copying" {
    nvim_runtime_fixture
    export WAYLAND_DISPLAY=fixture
    unset DISPLAY
    stub_bin wl-copy <<'EOF'
#!/bin/bash
exit 1
EOF
    for selection in '{"plugins":false}' '{"languages":[]}'; do
        printf '%s\n' "$selection" > "$XDG_CONFIG_HOME/nvim/envup.json"
        run "$NVIM_REAL" --headless -i NONE -n \
            "+lua assert(vim.g.clipboard and vim.g.clipboard.name == 'OSC 52')" +qa
        [ "$status" -eq 0 ]
        [[ "$output" != *'Error detected'* ]]
    done
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim Lazy mirror clones through transport without changing origin or user Git config" {
    local real_git; real_git="$(command -v git)" || skip "git not installed"
    nvim_runtime_fixture
    export REAL_GIT="$real_git" NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    export ENVUP_GH_MIRROR="file://$TEST_TMP/mirror's directory/"
    export GIT_CONFIG_PARAMETERS="'envup.existing=retained'"
    local source="$TEST_TMP/mirror's directory/https:/github.com/example/plugin.git"
    "$real_git" init -q "$source"
    printf 'mirror content\n' > "$source/content"
    "$real_git" -C "$source" add content
    "$real_git" -C "$source" -c user.name=Test -c user.email=test@example.com commit -qm fixture
    printf '[envup]\n  private = preserved\n' > "$HOME/.gitconfig"
    cp "$HOME/.gitconfig" "$TEST_TMP/gitconfig-before"
    cat > "$TEST_TMP/mirror.lua" <<'EOF'
local function git(args)
  table.insert(args, 1, vim.env.REAL_GIT)
  local out = vim.fn.system(args)
  assert(vim.v.shell_error == 0, out)
  return vim.trim(out)
end
local config = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lazy.lua")
local parameters = vim.env.GIT_CONFIG_PARAMETERS
dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lazy.lua")
assert(vim.env.GIT_CONFIG_PARAMETERS == parameters)
assert(config.git.url_format == nil)
assert(git({ "config", "envup.existing" }) == "retained")
local canonical = "https://github.com/example/plugin.git"
local dest = vim.env.HOME .. "/plugin"
git({ "clone", "--quiet", canonical, dest })
assert(git({ "-C", dest, "config", "remote.origin.url" }) == canonical)
assert(git({ "-C", dest, "remote", "get-url", "origin" }) == vim.env.ENVUP_GH_MIRROR .. canonical)
assert(vim.fn.readfile(dest .. "/content")[1] == "mirror content")
git({ "-C", dest, "fetch", "--quiet" })
git({ "-C", dest, "remote", "add", "vendor", "https://example.org/plugin.git" })
assert(git({ "-C", dest, "remote", "get-url", "vendor" }) == "https://example.org/plugin.git")
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/mirror.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    cmp "$HOME/.gitconfig" "$TEST_TMP/gitconfig-before"
    [ "$GIT_CONFIG_PARAMETERS" = "'envup.existing=retained'" ]
}

@test "nvim Lazy network budgets cap Git operations and reject invalid values" {
    nvim_runtime_fixture
    export NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    cat > "$TEST_TMP/budgets.lua" <<'EOF'
local path = vim.env.NVIM_SOURCE .. "/lua/configs/lazy.lua"
vim.env.ENVUP_NET_TIMEOUT = nil
vim.env.ENVUP_NET_TIMEOUT_NVIM = nil
assert(dofile(path).git.timeout == 120)
vim.env.ENVUP_NET_TIMEOUT = "9"
vim.env.ENVUP_NET_TIMEOUT_NVIM = "3"
assert(dofile(path).git.timeout == 3)
vim.env.ENVUP_NET_TIMEOUT_NVIM = "30"
assert(dofile(path).git.timeout == 9)
for _, name in ipairs({ "ENVUP_NET_TIMEOUT", "ENVUP_NET_TIMEOUT_NVIM" }) do
  for _, value in ipairs({ "0", "-1", "bad", "1.5", "1e999" }) do
    vim.env[name] = value
    local ok, err = pcall(dofile, path)
    assert(not ok and tostring(err):find(name .. " must be a positive integer", 1, true))
  end
  vim.env[name] = "10"
end
vim.env.GIT_CONFIG_PARAMETERS = "'envup.existing=retained'"
vim.env.ENVUP_GH_MIRROR = "https://mirror.example/"
-- Explicit offline mode must leave inherited Git routing alone.
package.loaded["configs.tools"].offline = function() return true end
dofile(path)
assert(vim.env.GIT_CONFIG_PARAMETERS == "'envup.existing=retained'")
vim.env.ENVUP_GH_MIRROR = nil
package.loaded["configs.tools"].offline = function() return false end
dofile(path)
assert(vim.env.GIT_CONFIG_PARAMETERS == "'envup.existing=retained'")
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/budgets.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
}

@test "Lazy verification catches task, cleanup, missing-plugin and configuration failures" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    cat > "$TEST_TMP/lazy-results.lua" <<'EOF'
local task = function(name, failed)
  return { name = name, has_errors = function() return failed end }
end
local plugin = { name = "fixture", _ = { installed = true, tasks = {} } }
local cleanup = { name = "obsolete", _ = { installed = false, tasks = {} } }
local config = { plugins = { fixture = plugin }, to_clean = { cleanup }, spec = { notifs = {} }, options = { headless = { process = true } } }
package.loaded["lazy.core.config"] = config
local invoked
package.loaded.lazy = {
  restore = function(opts) assert(opts.wait and opts.show == false and not config.options.headless.process); invoked = "restore" end,
  sync = function(opts) assert(opts.wait and opts.show == false); invoked = "sync"; config.to_clean = {} end,
}
local tools = require "configs.tools"
tools.ensure_plugins("restore")
assert(invoked == "restore")
for _, name in ipairs({ "fetch", "checkout", "build" }) do
  plugin._.tasks = { task(name, true) }
  local ok, err = pcall(tools.ensure_plugins, "restore")
  assert(not ok and tostring(err):find("fixture:" .. name, 1, true))
end
plugin._.tasks = { task("warning", false) }
tools.ensure_plugins("restore")
plugin._.installed = false
local ok, err = pcall(tools.ensure_plugins, "restore")
assert(not ok and tostring(err):find("fixture:not-installed", 1, true))
plugin._.installed = true
cleanup._.tasks = { task("clean", true) }
ok, err = pcall(tools.ensure_plugins, "sync")
assert(not ok and tostring(err):find("obsolete:clean", 1, true))
cleanup._.tasks = {}
tools.ensure_plugins("sync")
config.spec.notifs = { { level = vim.log.levels.ERROR, msg = "bad import" } }
ok, err = pcall(tools.ensure_plugins, "restore")
assert(not ok and tostring(err):find("configuration: bad import", 1, true))
config.spec.notifs = {}
tools.ensure_plugins("restore")
ok = pcall(tools.ensure_plugins, "invalid")
assert(not ok)
vim.env.ENVUP_NET = "offline"
ok = pcall(tools.ensure_plugins, "restore")
assert(not ok)
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/lazy-results.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim plugin errors and timeouts stop later installers and keep components" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0 ENVUP_NET_TIMEOUT_NVIM=1 ENVUP_NET_KILL_AFTER=1
    engine_verify() { return 0; }
    _nvim_plugins_enabled() { return 0; }
    _nvim_bootstrap_lazy() { return 0; }
    mkdir -p "$XDG_DATA_HOME"
    touch "$XDG_DATA_HOME/retained-component"
    for plugin_rc in 1 timeout; do
        export PLUGIN_RESULT="$plugin_rc"
        stub_bin nvim <<'EOF'
#!/bin/bash
if [[ "$*" == *ensure_plugins* ]]; then
    [[ "$PLUGIN_RESULT" == timeout ]] && exec sleep 5
    exit "$PLUGIN_RESULT"
fi
touch "$HOME/later-install-ran"
exit 0
EOF
        run post_install
        [ "$status" -eq 1 ]
        [[ "$output" == *"Lazy! sync failed"* && "$output" != *'nvim ready'* ]]
        [ ! -e "$HOME/later-install-ran" ]
        [ -e "$XDG_DATA_HOME/retained-component" ]
    done
}

@test "nvim plugin verification Lua errors become a failed headless exit" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    engine_verify() { return 0; }
    _nvim_plugins_enabled() { return 0; }
    _nvim_bootstrap_lazy() { return 0; }
    cat > "$XDG_CONFIG_HOME/nvim/init.lua" <<'EOF'
vim.opt.rtp:prepend(vim.fn.stdpath "config")
package.loaded["lazy.core.config"] = {
  plugins = { fixture = { name = "fixture", _ = { installed = false } } },
  spec = { notifs = {} },
  options = { headless = { process = true } },
}
package.loaded.lazy = { sync = function() end }
EOF
    run post_install
    [ "$status" -eq 1 ]
    [[ "$output" == *'fixture:not-installed'* && "$output" != *'nvim ready'* ]]
}

@test "nvim bootstrap distinguishes unavailable prerequisites from actual clone errors" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    engine_verify() { return 0; }
    _nvim_plugins_enabled() { return 0; }
    net_online() { return 0; }
    have() { return 1; }
    run post_install
    [ "$status" -eq 70 ]
    net_clone() { return 1; }
    have() { return 0; }
    run post_install
    [ "$status" -eq 1 ]
    [[ "$output" == *'cloning lazy.nvim failed'* && "$output" != *'nvim ready'* ]]
    [ ! -e "$HOME/network-ran" ]
}

@test "Mason mirrors GitHub asset templates and keeps provider and private settings" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0 NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    cat > "$TEST_TMP/mason-options.lua" <<'EOF'
local specs = dofile(vim.env.NVIM_SOURCE .. "/lua/plugins/init.lua")
local configure
for _, plugin in ipairs(specs) do
  if plugin[1] == "williamboman/mason.nvim" then configure = plugin.opts end
end
assert(configure)
for _, mirror in ipairs({ "https://mirror.example/", "https://mirror.example/a%20b///", "https://mirror.example/%s" }) do
  vim.env.ENVUP_GH_MIRROR = mirror
  local opts = { PATH = "skip", providers = { "private.provider" }, pip = { install_args = { "--no-deps" } } }
  configure(nil, opts)
  local prefix = mirror:gsub("/+$", "") .. "/https://github.com/"
  assert(opts.github.download_url_template:format("mason-org/mason-registry", "v1", "registry.json.zip")
    == prefix .. "mason-org/mason-registry/releases/download/v1/registry.json.zip")
  assert(opts.github.download_url_template:format("llvm/llvm-project", "v2", "clangd.zip")
    == prefix .. "llvm/llvm-project/releases/download/v2/clangd.zip")
  local template = opts.github.download_url_template
  configure(nil, opts)
  assert(opts.github.download_url_template == template)
  assert(opts.PATH == "skip" and opts.providers[1] == "private.provider" and opts.pip.install_args[1] == "--no-deps")
end
local private = { github = { download_url_template = "https://private.example/%s/%s/%s" } }
configure(nil, private)
assert(private.github.download_url_template == "https://private.example/%s/%s/%s")
vim.env.ENVUP_GH_MIRROR = nil
local direct = {}
configure(nil, direct)
assert(direct.github == nil)
vim.env.ENVUP_GH_MIRROR = "https://mirror.example"
vim.env.ENVUP_NET = "offline"
local offline = {}
configure(nil, offline)
assert(offline.github == nil)
-- Even online, loading the LSP bridge must never start tool installation.
vim.env.ENVUP_NET = "auto"
package.loaded["mason-lspconfig"] = { setup = function(opts)
  assert(#opts.ensure_installed == 0 and opts.automatic_installation == false)
end }
for _, plugin in ipairs(specs) do
  if plugin[1] == "williamboman/mason-lspconfig.nvim" then plugin.config() end
end
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/mason-options.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim explicit Mason errors and watchdog timeouts fail while keeping installed components" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0 ENVUP_NET_TIMEOUT_NVIM=1 ENVUP_NET_KILL_AFTER=1
    engine_verify() { return 0; }
    _nvim_plugins_enabled() { return 0; }
    _nvim_bootstrap_lazy() { return 0; }
    mkdir -p "$XDG_DATA_HOME"
    touch "$XDG_DATA_HOME/retained-component"
    run_post() {
        local rc=0
        post_install || rc=$?
        printf 'reason=%s\n' "$_ENG_HOOK_REASON"
        return "$rc"
    }
    stub_bin nvim <<'EOF'
#!/bin/bash
if [[ "$*" == *".ensure()"* ]]; then
    touch "$HOME/mason-started"
    exit 1
fi
exit 0
EOF
    run run_post
    [ "$status" -eq 1 ]
    [[ "$output" == *'language-tool installation failed (exit 1)'* && "$output" != *'nvim ready'* ]]
    [ -e "$HOME/mason-started" ]
    [ -e "$XDG_DATA_HOME/retained-component" ]
    stub_bin nvim <<'EOF'
#!/bin/bash
if [[ "$*" == *".ensure()"* ]]; then exec sleep 5; fi
exit 0
EOF
    run run_post
    [ "$status" -eq 1 ]
    [[ "$output" == *'language-tool installation failed (exit 124)'* && "$output" != *'nvim ready'* ]]
    [ -e "$XDG_DATA_HOME/retained-component" ]
}

@test "Treesitter installs only unusable selected parsers synchronously and verifies the result" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0 NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    printf '{"languages":["c","cpp"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    cat > "$TEST_TMP/parsers.lua" <<'EOF'
local available, calls = { c = true }, 0
vim.treesitter.language.add = function(language)
  assert(available[language], "missing " .. language)
end
local tools = require "configs.tools"
local install = { commands = { TSInstallSync = {} } }
install.commands.TSInstallSync["run!"] = function(languages)
  calls = calls + 1
  assert(install.prefer_git and vim.deep_equal(languages, { "cpp" }))
  available.cpp = true
end
package.loaded["nvim-treesitter.install"] = install
tools.ensure_parsers()
tools.ensure_parsers()
assert(calls == 1 and #tools.missing_parsers() == 0)
available.cpp = nil
install.commands.TSInstallSync["run!"] = function() calls = calls + 1 end
local ok, err = pcall(tools.ensure_parsers)
assert(not ok and tostring(err):find("unavailable after install: cpp", 1, true))
vim.env.ENVUP_NET = "offline"
ok, err = pcall(tools.ensure_parsers)
assert(not ok and tostring(err):find("unavailable while offline: cpp", 1, true) and calls == 2)
for _, selection in ipairs({ '{"languages":[]}', '{"plugins":false}' }) do
  vim.fn.writefile({ selection }, vim.fn.stdpath("config") .. "/envup.json")
  dofile(vim.env.NVIM_SOURCE .. "/lua/configs/tools.lua").ensure_parsers()
end
assert(calls == 2)
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/parsers.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim parser install errors and timeouts fail without reporting ready or deleting components" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0 ENVUP_NET_TIMEOUT_NVIM=1 ENVUP_NET_KILL_AFTER=1
    engine_verify() { return 0; }
    _nvim_plugins_enabled() { return 0; }
    _nvim_bootstrap_lazy() { return 0; }
    mkdir -p "$XDG_DATA_HOME"
    touch "$XDG_DATA_HOME/retained-component"
    for parser_rc in 1 timeout; do
        export PARSER_RESULT="$parser_rc"
        stub_bin nvim <<'EOF'
#!/bin/bash
if [[ "$*" == *ensure_parsers* ]]; then
    [[ "$PARSER_RESULT" == timeout ]] && exec sleep 5
    exit "$PARSER_RESULT"
fi
exit 0
EOF
        run post_install
        [ "$status" -eq 1 ]
        if [[ "$parser_rc" == timeout ]]; then
            [[ "$output" == *'parser installation failed (exit 124)'* ]]
        else
            [[ "$output" == *'parser installation failed (exit 1)'* ]]
        fi
        [[ "$output" != *'nvim ready'* ]]
        [ -e "$XDG_DATA_HOME/retained-component" ]
    done
}

@test "nvim parser health rejects corrupt cache without executing init or fetching" {
    nvim_runtime_fixture
    printf '{"languages":["html"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    printf '{}\n' > "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    mkdir -p "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy" "$XDG_DATA_HOME/nvim/base46" \
        "$XDG_DATA_HOME/nvim/lazy/nvim-treesitter/parser"
    touch "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua" \
        "$XDG_DATA_HOME/nvim/base46/defaults" "$XDG_DATA_HOME/nvim/base46/statusline"
    printf 'corrupt parser\n' > "$XDG_DATA_HOME/nvim/lazy/nvim-treesitter/parser/html.so"
    run check_health
    [ "$status" -eq 70 ]
    [[ "$output" == *'parser:html'* ]]
    [ "$(cat "$XDG_DATA_HOME/nvim/lazy/nvim-treesitter/parser/html.so")" = 'corrupt parser' ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_STATE_HOME" ]
}

@test "nvim online and offline cold startup edits and saves without bootstrapping Lazy" {
    nvim_runtime_fixture
    printf 'vim.g.private_loaded = true\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    local flag
    for flag in net legacy online; do
        if [[ "$flag" == net ]]; then export ENVUP_NET=offline ENVUP_OFFLINE=0
        elif [[ "$flag" == legacy ]]; then export ENVUP_NET=auto ENVUP_OFFLINE=1
        else export ENVUP_NET=auto ENVUP_OFFLINE=0; fi
        run "$NVIM_REAL" --headless -i NONE -n "$TEST_TMP/offline.txt" \
            '+lua assert(vim.g.private_loaded); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"offline edit"})' +write +qa
        [ "$status" -eq 0 ]
        [[ "$output" == *'lazy.nvim missing'* && "$output" == *'using core editing'* ]]
        [[ "$flag" == online ]] || [[ "$output" == *'offline: lazy.nvim missing'* ]]
        [ "$(cat "$TEST_TMP/offline.txt")" = 'offline edit' ]
        [ ! -e "$HOME/network-ran" ]
        [ ! -e "$XDG_DATA_HOME/nvim/lazy" ]
    done
}

@test "nvim reports private override errors without stopping editing or later overrides" {
    nvim_runtime_fixture
    printf '{"plugins":false}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    local host; host="$(hostname)"; host="${host%%.*}"
    mkdir -p "$XDG_CONFIG_HOME/nvim/hosts"
    local hostfile="$XDG_CONFIG_HOME/nvim/hosts/$host.lua"
    printf 'error("host override failed")\n' > "$hostfile"
    printf 'vim.g.private_loaded = true\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    run "$NVIM_REAL" --headless -i NONE -n "$TEST_TMP/override.txt" \
        '+lua assert(vim.g.private_loaded); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"edit after error"})' +write +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *"$hostfile"* && "$output" == *'host override failed'* ]]
    [ "$(cat "$TEST_TMP/override.txt")" = 'edit after error' ]

    printf 'vim.g.override_order = {"host"}\n' > "$hostfile"
    # Vim globals return a copy of list values; assign the updated list back.
    printf 'local order = vim.g.override_order; order[#order+1] = "local"; vim.g.override_order = order\n' \
        > "$XDG_CONFIG_HOME/nvim/local.lua"
    run "$NVIM_REAL" --headless -i NONE -n \
        '+lua assert(vim.deep_equal(vim.g.override_order, {"host", "local"}))' +qa
    [ "$status" -eq 0 ]
    [[ "$output" != *'[envup]'* ]]

    printf 'invalid Lua syntax\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    run "$NVIM_REAL" --headless -i NONE -n '+lua assert(vim.g.override_order[1] == "host")' +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *"$XDG_CONFIG_HOME/nvim/local.lua"* ]]
    rm -f "$hostfile" "$XDG_CONFIG_HOME/nvim/local.lua"
    run "$NVIM_REAL" --headless -i NONE -n +qa
    [ "$status" -eq 0 ]
    [[ "$output" != *'[envup]'* ]]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim offline partial cache falls back and install preserves it without restore or clone" {
    nvim_runtime_fixture
    printf '{"languages":[]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    cp "$(NV lazy-lock.json)" "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    mkdir -p "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy"
    printf 'error("partial cache must not be loaded")\n' > "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
    printf 'retained\n' > "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/private-marker"
    run "$NVIM_REAL" --headless -i NONE -n "$TEST_TMP/partial.txt" \
        '+lua vim.api.nvim_buf_set_lines(0, 0, -1, false, {"partial cache edit"})' +write +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *'cached plugins incomplete'* ]]
    [ "$(cat "$TEST_TMP/partial.txt")" = 'partial cache edit' ]
    run post_install
    [ "$status" -eq 70 ]
    [[ "$output" == *'plugin:NvChad'* ]]
    [ "$(cat "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/private-marker")" = retained ]
    printf '{}\n' > "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    cp "$ENVUP_HOME/modules/nvim/files/lazy-lock.json" "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
    run env -u ENVUP_HOME "$NVIM_REAL" --headless -i NONE -n +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *'base46:defaults'* && "$output" == *'base46:statusline'* ]]
    rm "$XDG_CONFIG_HOME/nvim/lazy-lock.json"
    run env -u ENVUP_HOME "$NVIM_REAL" --headless -i NONE -n +qa
    [ "$status" -eq 0 ]
    [[ "$output" == *'cache check failed'* ]]
    rm "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
    run _nvim_bootstrap_lazy
    [ "$status" -eq 78 ]
    [ "$(cat "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/private-marker")" = retained ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim offline warm acceptance skips restore and disables automatic plugin and resource installs" {
    nvim_runtime_fixture
    printf '{"languages":["c","cpp"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    export NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    cat > "$TEST_TMP/offline-options.lua" <<'EOF'
local tools = require "configs.tools"
assert(tools.offline() and #tools.mason_tools == 2)
local lazy = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lazy.lua")
assert(lazy.install.missing == false and lazy.checker.enabled == false)
package.loaded["configs.conform"] = {}
package.loaded["mason-lspconfig"] = { setup = function(opts)
  assert(#opts.ensure_installed == 0 and opts.automatic_installation == false)
end }
for _, plugin in ipairs(dofile(vim.env.NVIM_SOURCE .. "/lua/plugins/init.lua")) do
  if plugin[1] == "williamboman/mason-lspconfig.nvim" then plugin.config() end
  if plugin[1] == "nvim-treesitter/nvim-treesitter" then
    local opts = { ensure_installed = { "cpp" }, auto_install = true }
    plugin.opts(nil, opts)
    assert(#opts.ensure_installed == 0 and opts.auto_install == false)
  end
end
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/offline-options.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    _nvim_headless() { touch "$HOME/restore-ran"; return 1; }
    check_health() { return 0; }
    run post_install
    [ "$status" -eq 0 ]
    [[ "$output" == *'without restore or sync'* ]]
    [ ! -e "$HOME/restore-ran" ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim language selection reaches LSP, formatter and parser consumers without inherited defaults" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    export NVIM_SOURCE="$REPO_ROOT/modules/nvim/files"
    cat > "$TEST_TMP/languages.lua" <<'EOF'
local cases = {
  { {}, 9, { "clangd", "pyright", "lua_ls", "bashls" }, 12 },
  { { languages = { "c", "cpp", "c" } }, 2, { "clangd" }, 2 },
  { { languages = { "python" } }, 2, { "pyright" }, 1 },
  { { languages = { "lua" } }, 2, { "lua_ls" }, 1 },
  { { languages = { "bash" } }, 2, { "bashls" }, 1 },
  { { languages = { "json", "yaml", "markdown" } }, 1, {}, 3 },
  { { languages = { "html", "css", "vim", "vimdoc" } }, 0, {}, 4 },
  { { languages = {} }, 0, {}, 0 },
}
for _, case in ipairs(cases) do
  -- Encode the empty choice as an array, not an object.
  local text = next(case[1]) == nil and "{}" or vim.json.encode(case[1])
  vim.fn.writefile({ text }, vim.fn.stdpath("config") .. "/envup.json")
  local tools = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/tools.lua")
  assert(#tools.mason_tools == case[2])
  assert(vim.deep_equal(tools.lsp_servers, case[3]))
  assert(#tools.treesitter_parsers == case[4])
  package.loaded["configs.tools"] = tools
  package.loaded["configs.conform"] = dofile(vim.env.NVIM_SOURCE .. "/lua/configs/conform.lua")
  package.loaded["nvchad.configs.lspconfig"] = {}
  local configured = {}
  package.loaded.lspconfig = setmetatable({}, { __index = function(_, server)
    return { setup = function() configured[#configured + 1] = server end }
  end })
  dofile(vim.env.NVIM_SOURCE .. "/lua/configs/lspconfig.lua")
  assert(vim.deep_equal(configured, case[3]))
  for _, plugin in ipairs(dofile(vim.env.NVIM_SOURCE .. "/lua/plugins/init.lua")) do
    if plugin[1] == "nvim-treesitter/nvim-treesitter" then
      local opts = { ensure_installed = { "lua", "python" }, auto_install = true, highlight = { enable = true } }
      plugin.opts(nil, opts)
      assert(#opts.ensure_installed == 0 and plugin.build == false)
      assert(opts.auto_install == false and opts.highlight.enable)
    elseif plugin[1] == "stevearc/conform.nvim" then
      local opts = plugin.opts(nil, { formatters_by_ft = { lua = { "stylua" } } })
      assert(vim.deep_equal(opts.formatters_by_ft, tools.formatters_by_ft))
      if case[2] == 0 then assert(next(opts.formatters_by_ft) == nil) end
      if case[1].languages and case[1].languages[1] == "bash" then
        assert(opts.formatters_by_ft.sh[1] == "shfmt" and opts.formatters_by_ft.bash[1] == "shfmt")
      end
    end
  end
end
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/languages.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim selected C and C++ tools are requested once from Mason and verified afterward" {
    nvim_runtime_fixture
    export ENVUP_NET=auto ENVUP_OFFLINE=0
    printf '{"languages":["c","cpp"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    cat > "$TEST_TMP/install-languages.lua" <<'EOF'
local installed, requested, probes = {}, {}, {}
vim.fn.executable = function() return 1 end
vim.system = function(cmd)
  probes[cmd[1]] = (probes[cmd[1]] or 0) + 1
  return { wait = function() return { code = installed[cmd[1]] and 0 or 1 } end }
end
package.loaded["mason.api.command"] = { MasonInstall = function(packages, options)
  assert(options.force and options.strict)
  for _, name in ipairs(packages) do
    assert(not installed[name], "duplicate install: " .. name)
    installed[name] = true
    requested[#requested + 1] = name
  end
end }
require("configs.tools").ensure()
assert(vim.deep_equal(requested, { "clangd", "clang-format" }))
assert(probes.clangd == 2 and probes["clang-format"] == 2 and not probes.pyright and not probes.ruff)
EOF
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua local ok, err = pcall(dofile, '$TEST_TMP/install-languages.lua'); if not ok then print(err); vim.cmd('cquit 1') end" +qa
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim selected language health ignores unselected broken tools but reports selected failures" {
    nvim_runtime_fixture
    # This test isolates executable selection; parser loading is covered separately.
    { printf 'vim.treesitter.language.add = function() end\n'; cat "$(TOOLS)"; } \
        > "$ENVUP_HOME/modules/nvim/files/lua/configs/tools.lua"
    printf '{"languages":["c","cpp"]}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    printf '{}\n' > "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    mkdir -p "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy"
    touch "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
    mkdir -p "$XDG_DATA_HOME/nvim/base46"
    touch "$XDG_DATA_HOME/nvim/base46/defaults" "$XDG_DATA_HOME/nvim/base46/statusline"
    local tool
    for tool in pyright pyright-langserver ruff lua-language-server stylua bash-language-server shfmt prettier; do
        printf '#!/bin/bash\ntouch "$HOME/unselected-ran"\nexit 1\n' > "$STUB_BIN/$tool"
        chmod +x "$STUB_BIN/$tool"
    done
    for tool in clangd clang-format; do
        printf '#!/bin/bash\nexit 0\n' > "$STUB_BIN/$tool"
        chmod +x "$STUB_BIN/$tool"
    done
    run check_health
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/unselected-ran" ]
    printf '#!/bin/bash\nexit 1\n' > "$STUB_BIN/clangd"
    run check_health
    [ "$status" -eq 70 ]
    [[ "$output" == *clangd* && "$output" != *pyright* ]]
    run "$NVIM_REAL" --headless -u NONE -i NONE -n --noplugin \
        "+lua require('configs.tools').ensure()" +qa
    [ "$status" -eq 1 ]
    [[ "$output" == *'while offline: clangd'* && "$output" != *pyright* ]]
    [ ! -e "$HOME/unselected-ran" ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_STATE_HOME" ]
}

@test "nvim persistent core mode edits files and loads host then private overrides without bootstrap" {
    nvim_runtime_fixture
    printf '{"plugins":false}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    mkdir -p "$XDG_CONFIG_HOME/nvim/hosts"
    printf 'vim.g.override_order = "host"\n' > "$XDG_CONFIG_HOME/nvim/hosts/$(hostname -s).lua"
    printf 'vim.g.override_order = vim.g.override_order .. ",local"\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    run "$NVIM_REAL" --headless -i NONE -n "$TEST_TMP/edit.txt" \
        '+lua assert(vim.g.override_order == "host,local"); vim.api.nvim_buf_set_lines(0, 0, -1, false, {"edited in core mode"})' +write +qa
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_TMP/edit.txt")" = 'edited in core mode' ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_DATA_HOME/nvim/lazy" ]
}

@test "nvim core selection skips installation and checks without executing private Lua or tools" {
    nvim_runtime_fixture
    printf '{"plugins":false}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    printf 'vim.fn.writefile({"unexpected"}, "%s")\n' "$HOME/private-ran" > "$XDG_CONFIG_HOME/nvim/local.lua"
    stub_bin clangd <<'EOF'
#!/bin/bash
touch "$HOME/tool-ran"
exit 1
EOF
    run post_install
    [ "$status" -eq 0 ]
    [[ "$output" == *'core mode'* ]]
    run check_health
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/private-ran" ]
    [ ! -e "$HOME/tool-ran" ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_DATA_HOME" ]
    [ ! -e "$XDG_STATE_HOME" ]
    [ ! -e "$XDG_CACHE_HOME" ]
}

@test "nvim rejects malformed capability data before plugin bootstrap" {
    nvim_runtime_fixture
    local config
    for config in 'not json' '[]' '{"plugins":"false"}' '{"plugin":false}' '{"plugins":null}' \
        '{"languages":null}' '{"languages":{}}' '{"languages":"cpp"}' \
        '{"languages":["rust"]}' '{"languages":[false]}' '{"languages":[null]}'; do
        printf '%s\n' "$config" > "$XDG_CONFIG_HOME/nvim/envup.json"
        run post_install
        [ "$status" -eq 1 ]
        run check_health
        [ "$status" -eq 1 ]
        [ ! -e "$HOME/network-ran" ]
    done
    rm "$XDG_CONFIG_HOME/nvim/envup.json"
    ln -s "$TEST_TMP/missing-selection" "$XDG_CONFIG_HOME/nvim/envup.json"
    run post_install
    [ "$status" -eq 1 ]
    [ ! -e "$HOME/network-ran" ]
}

@test "nvim absent selection retains plugin checks and core selection survives uninstall" {
    nvim_runtime_fixture
    cp "$(NV lazy-lock.json)" "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    run check_health
    [ "$status" -eq 70 ]
    [[ "$output" == *'plugin:NvChad'* ]]
    printf '{"plugins":false}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    cp "$REPO_ROOT/modules/nvim/meta.sh" "$ENVUP_HOME/modules/nvim/meta.sh"
    cp "$REPO_ROOT/modules/nvim/hooks.sh" "$ENVUP_HOME/modules/nvim/hooks.sh"
    run engine_uninstall nvim
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/envup.json")" = '{"plugins":false}' ]
}

@test "nvim core CLI install succeeds without running Git or fetching plugin dependencies" {
    nvim_runtime_fixture
    printf '{"plugins":false}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    cp "$REPO_ROOT/envup" "$ENVUP_HOME/envup"
    cp "$REPO_ROOT/VERSION" "$ENVUP_HOME/VERSION"
    cp "$REPO_ROOT/modules/nvim/meta.sh" "$ENVUP_HOME/modules/nvim/meta.sh"
    cp "$REPO_ROOT/modules/nvim/hooks.sh" "$ENVUP_HOME/modules/nvim/hooks.sh"
    cp "$(INIT)" "$ENVUP_HOME/modules/nvim/files/init.lua"
    cp "$(NV lazy-lock.json)" "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    mkdir -p "$ENVUP_HOME/modules/nvim/files/hosts"
    isolate_path nvim
    rm "$STUB_BIN/git" "$TEST_TMP/isolated-bin/git"
    ! command -v git
    run "$ENVUP_HOME/envup" install nvim
    [ "$status" -eq 0 ]
    [[ "$output" != *'installing prerequisites'* ]]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_DATA_HOME" ]
    manifest_has nvim
    run "$ENVUP_HOME/envup" status --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"state":"ok"'* ]]
    [ ! -e "$HOME/network-ran" ]
}

nvim_deploy_fixture() {
    export XDG_CONFIG_HOME="$HOME/.config" ENVUP_NVIM_LAZY=skip ENVUP_LIBC=glibc-2.34
    cp -R "$REPO_ROOT/modules/nvim" "$ENVUP_HOME/modules/nvim"
    stub_bin nvim <<'EOF'
#!/bin/bash
echo 'NVIM v0.10.4'
EOF
}

@test "nvim fresh deployment excludes checkout-local config and preserves live shared links" {
    nvim_deploy_fixture
    printf 'private checkout\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    printf '{"plugins":false}\n' > "$ENVUP_HOME/modules/nvim/files/envup.json"
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ ! -e "$XDG_CONFIG_HOME/nvim/local.lua" ]
    [ ! -e "$XDG_CONFIG_HOME/nvim/envup.json" ]
    [ -L "$XDG_CONFIG_HOME/nvim/init.lua" ]
    [ -L "$XDG_CONFIG_HOME/nvim/lua" ]
    printf 'shared update\n' >> "$ENVUP_HOME/modules/nvim/files/init.lua"
    [[ "$(tail -1 "$XDG_CONFIG_HOME/nvim/init.lua")" == 'shared update' ]]
    [ "$(authoring_links_unique nvim)" -eq 0 ]
}

@test "nvim legacy directory migration copies private file and survives reinstall and uninstall" {
    nvim_deploy_fixture
    mkdir -p "$XDG_CONFIG_HOME"
    printf 'old private\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    printf '{"plugins":false}\n' > "$ENVUP_HOME/modules/nvim/files/envup.json"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    [ "$(authoring_links_unique nvim)" -eq 0 ]
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ ! -L "$XDG_CONFIG_HOME/nvim/local.lua" ]
    [ ! -L "$XDG_CONFIG_HOME/nvim/envup.json" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/envup.json")" = '{"plugins":false}' ]
    [ -L "$(backup_path "$XDG_CONFIG_HOME/nvim")" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = 'old private' ]
    printf 'new private\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    printf '{"plugins":true}\n' > "$XDG_CONFIG_HOME/nvim/envup.json"
    [ "$(cat "$ENVUP_HOME/modules/nvim/files/envup.json")" = '{"plugins":false}' ]
    [ "$(cat "$ENVUP_HOME/modules/nvim/files/local.lua")" = 'old private' ]
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = 'new private' ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/envup.json")" = '{"plugins":true}' ]
    run engine_uninstall nvim
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = 'new private' ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/envup.json")" = '{"plugins":true}' ]
    [ ! -e "$XDG_CONFIG_HOME/nvim/init.lua" ]
    [ -f "$ENVUP_HOME/modules/nvim/files/init.lua" ]
}

@test "doctor repairs Nvim legacy configuration locally and preserves private files" {
    nvim_deploy_fixture
    export XDG_CONFIG_HOME="$TEST_TMP/config with spaces" XDG_DATA_HOME="$TEST_TMP/data"
    mkdir -p "$XDG_CONFIG_HOME"
    printf 'private\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    printf '{"plugins":false}\n' > "$ENVUP_HOME/modules/nvim/files/envup.json"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    manifest_add nvim
    run doctor_main --fix --module nvim
    [ "$status" -eq 0 ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ -L "$XDG_CONFIG_HOME/nvim/init.lua" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/envup.json")" = '{"plugins":false}' ]
    [ -L "$(backup_path "$XDG_CONFIG_HOME/nvim")" ]
    [ ! -L "$ENVUP_HOME/modules/nvim/files/init.lua" ]
    printf 'edited private\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    run doctor_main --fix --module nvim
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = 'edited private' ]
    [ "$(cat "$ENVUP_HOME/modules/nvim/files/local.lua")" = private ]
    [ ! -e "$XDG_DATA_HOME/nvim/lazy" ]
}

@test "doctor creates a missing registered Nvim config without importing checkout-private files" {
    nvim_deploy_fixture
    printf 'another user\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    manifest_add nvim
    run doctor_main --fix --module nvim
    [ "$status" -eq 0 ]
    [ -d "$XDG_CONFIG_HOME/nvim" ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ -L "$XDG_CONFIG_HOME/nvim/init.lua" ]
    [ ! -e "$XDG_CONFIG_HOME/nvim/local.lua" ]
}

@test "doctor refuses a foreign Nvim directory even when its managed file links are healthy" {
    nvim_deploy_fixture
    local foreign="$TEST_TMP/foreign"
    mkdir -p "$foreign" "$XDG_CONFIG_HOME"
    local name
    for name in init.lua lua hosts lazy-lock.json; do
        ln -s "$ENVUP_HOME/modules/nvim/files/$name" "$foreign/$name"
    done
    printf 'foreign private\n' > "$foreign/local.lua"
    ln -s "$foreign" "$XDG_CONFIG_HOME/nvim"
    manifest_add nvim
    run doctor_main --fix --module nvim
    [ "$status" -ne 0 ]
    [[ "$output" == *'nvim config points outside this checkout'* ]]
    [[ "$output" != *'this machine is healthy'* ]]
    [ "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$foreign" ]
    [ "$(cat "$foreign/local.lua")" = 'foreign private' ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "nvim existing real config keeps private and unrelated files under custom XDG root" {
    nvim_deploy_fixture
    export XDG_CONFIG_HOME="$TEST_TMP/custom-config"
    mkdir -p "$XDG_CONFIG_HOME/nvim"
    printf 'user private\n' > "$XDG_CONFIG_HOME/nvim/local.lua"
    printf 'user init\n' > "$XDG_CONFIG_HOME/nvim/init.lua"
    touch "$XDG_CONFIG_HOME/nvim/unrelated"
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = 'user private' ]
    [ "$(cat "$(backup_path "$XDG_CONFIG_HOME/nvim/init.lua")")" = 'user init' ]
    [ -e "$XDG_CONFIG_HOME/nvim/unrelated" ]
    [ ! -e "$HOME/.config/nvim" ]
}

@test "nvim dry-run leaves fresh and legacy config directories untouched" {
    nvim_deploy_fixture
    export ENVUP_DRY_RUN=1
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_CONFIG_HOME/nvim" ]
    mkdir -p "$XDG_CONFIG_HOME"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ -L "$XDG_CONFIG_HOME/nvim" ]
    [ ! -e "$ENVUP_BACKUP_DIR" ]
}

@test "nvim refuses foreign or dangling config directory links without writing through them" {
    nvim_deploy_fixture
    mkdir -p "$XDG_CONFIG_HOME" "$TEST_TMP/foreign"
    printf 'foreign private\n' > "$TEST_TMP/foreign/local.lua"
    ln -s "$TEST_TMP/foreign" "$XDG_CONFIG_HOME/nvim"
    run engine_install nvim
    [ "$status" -eq 1 ]
    [ "$(readlink "$XDG_CONFIG_HOME/nvim")" = "$TEST_TMP/foreign" ]
    [ ! -e "$TEST_TMP/foreign/init.lua" ]
    [ "$(cat "$TEST_TMP/foreign/local.lua")" = 'foreign private' ]
    rm "$XDG_CONFIG_HOME/nvim"
    ln -s "$TEST_TMP/missing" "$XDG_CONFIG_HOME/nvim"
    run engine_install nvim
    [ "$status" -eq 1 ]
    [ -L "$XDG_CONFIG_HOME/nvim" ]
}

@test "nvim migration backup conflict preserves legacy link and can be retried" {
    nvim_deploy_fixture
    mkdir -p "$XDG_CONFIG_HOME" "$(dirname "$(backup_path "$XDG_CONFIG_HOME/nvim")")"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    printf 'private\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    touch "$(backup_path "$XDG_CONFIG_HOME/nvim")"
    run engine_install nvim
    [ "$status" -eq 1 ]
    [ -L "$XDG_CONFIG_HOME/nvim" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
    rm "$(backup_path "$XDG_CONFIG_HOME/nvim")"
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
}

@test "nvim failed private copy leaves legacy config usable and no staged directory" {
    nvim_deploy_fixture
    mkdir -p "$XDG_CONFIG_HOME"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    printf 'private\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    stub_bin cp <<'EOF'
#!/bin/bash
printf partial > "${@: -1}"
exit 1
EOF
    hash -r
    [ "$(command -v cp)" = "$STUB_BIN/cp" ]
    run engine_install nvim
    [ "$status" -eq 1 ]
    [ -L "$XDG_CONFIG_HOME/nvim" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
    [ ! -e "$ENVUP_BACKUP_DIR/.config/nvim" ]
    local -a staged=("$XDG_CONFIG_HOME"/nvim.envup.*)
    [ ! -e "${staged[0]}" ]
}

@test "nvim failed directory activation restores legacy link before retry" {
    nvim_deploy_fixture
    mkdir -p "$XDG_CONFIG_HOME"
    ln -s "$ENVUP_HOME/modules/nvim/files" "$XDG_CONFIG_HOME/nvim"
    printf 'private\n' > "$ENVUP_HOME/modules/nvim/files/local.lua"
    local real_mv; real_mv="$(command -v mv)"
    export NVIM_TEST_MV="$real_mv"
    stub_bin mv <<'EOF'
#!/bin/bash
[[ "$1" == *.envup.* ]] && exit 1
exec "$NVIM_TEST_MV" "$@"
EOF
    run engine_install nvim
    [ "$status" -eq 1 ]
    [ -L "$XDG_CONFIG_HOME/nvim" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
    [ ! -L "$(backup_path "$XDG_CONFIG_HOME/nvim")" ]
    rm "$STUB_BIN/mv"
    run engine_install nvim
    [ "$status" -eq 0 ]
    [ ! -L "$XDG_CONFIG_HOME/nvim" ]
    [ "$(cat "$XDG_CONFIG_HOME/nvim/local.lua")" = private ]
}

@test "every lua file added here parses" {
    local lua; lua="$(lua_bin)" || skip "no lua interpreter"
    [[ -n "$lua" ]] || skip "no lua interpreter"
    local f
    for f in "$(OPTIONS)" "$(CONFORM)" "$(TOOLS)" "$(BIGFILE)" "$(LSPCFG)" "$(PLUGINS)" "$(MAPPINGS)" "$(INIT)"; do
        run "$lua" -e "assert(loadfile('$f'))"
        [ "$status" -eq 0 ] || { echo "$f: $output"; return 1; }
    done
}

@test "nvim component health checks caches and executable failures without bootstrap or writes" {
    local nvim; nvim="$(command -v nvim)" || skip "nvim not installed"
    version_ge "$(bin_version nvim)" 0.10 || skip "requires nvim >= 0.10"
    export XDG_DATA_HOME="$TEST_TMP/data" XDG_STATE_HOME="$TEST_TMP/state-nvim"
    export XDG_CACHE_HOME="$TEST_TMP/cache" XDG_CONFIG_HOME="$TEST_TMP/config"
    export NVIM_APPNAME=nvim
    mkdir -p "$ENVUP_HOME/modules/nvim/files/lua/configs" "$XDG_CONFIG_HOME/nvim"
    # Isolate plugin and executable health from parser availability on the test host.
    { printf 'vim.treesitter.language.add = function() end\n'; cat "$(TOOLS)"; } \
        > "$ENVUP_HOME/modules/nvim/files/lua/configs/tools.lua"
    cp "$(NV lazy-lock.json)" "$ENVUP_HOME/modules/nvim/files/lazy-lock.json"
    cp "$REPO_ROOT/modules/nvim/hooks.sh" "$ENVUP_HOME/modules/nvim/hooks.sh"
    printf 'NAME=nvim\nVERIFY_BIN=nvim\nVERIFY_MIN_VERSION=0.10\n' > "$ENVUP_HOME/modules/nvim/meta.sh"
    printf 'vim.fn.writefile({"unexpected"}, "%s")\n' "$HOME/init-ran" > "$XDG_CONFIG_HOME/nvim/init.lua"
    stub_bin git <<'EOF'
#!/bin/bash
touch "$HOME/network-ran"
exit 1
EOF
    local tool
    for tool in clangd pyright pyright-langserver lua-language-server bash-language-server clang-format stylua ruff shfmt prettier; do
        printf '#!/bin/bash\necho fixture-1.0\n' > "$STUB_BIN/$tool"
        chmod +x "$STUB_BIN/$tool"
    done
    manifest_add nvim
    run health_probe nvim
    [[ "$output" == *$'state\tdegraded'* ]]
    [[ "$output" == *"plugin:NvChad"* ]]
    [ ! -e "$HOME/init-ran" ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_DATA_HOME" ]
    [ ! -e "$XDG_STATE_HOME" ]
    [ ! -e "$XDG_CACHE_HOME" ]

    python3 -c 'import json,os,sys; data=json.load(open(sys.argv[1])); [os.makedirs(os.path.join(sys.argv[2],n)) for n in data]' \
        "$ENVUP_HOME/modules/nvim/files/lazy-lock.json" "$XDG_DATA_HOME/nvim/lazy"
    mkdir -p "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy"
    touch "$XDG_DATA_HOME/nvim/lazy/lazy.nvim/lua/lazy/init.lua"
    mkdir -p "$XDG_DATA_HOME/nvim/base46"
    touch "$XDG_DATA_HOME/nvim/base46/defaults" "$XDG_DATA_HOME/nvim/base46/statusline"
    run health_probe nvim
    [[ "$output" == *$'state\tok'* ]]
    printf '#!/bin/bash\nexit 1\n' > "$STUB_BIN/clangd"
    run health_probe nvim
    [[ "$output" == *$'state\tdegraded'* ]]
    [[ "$output" == *"unusable: clangd"* ]]
    [ ! -e "$HOME/init-ran" ]
    [ ! -e "$HOME/network-ran" ]
    [ ! -e "$XDG_STATE_HOME" ]
    [ ! -e "$XDG_CACHE_HOME" ]
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

@test "every configured language tool is installed from one inventory" {
    for package in clangd pyright lua-language-server bash-language-server \
                   clang-format stylua ruff shfmt prettier; do
        grep -q "package = \"$package\"" "$(TOOLS)"
    done
    grep -q 'formatters_by_ft = tools.formatters_by_ft' "$(CONFORM)"
    grep -q 'ensure_installed = {}' "$(PLUGINS)"
}

@test "the install hook waits for and verifies Mason tools" {
    grep -q "require('configs.tools').ensure()" "$REPO_ROOT/modules/nvim/hooks.sh"
    grep -q 'nvim LSP servers and formatters' "$REPO_ROOT/modules/nvim/hooks.sh"
    grep -q 'unavailable after install' "$(TOOLS)"
    grep -q 'vim.system(tool.probe' "$(TOOLS)"
}

@test "portable formatter builds are selected on old Linux hosts" {
    grep -q 'package = "stylua".*portable = true' "$(TOOLS)"
    grep -q 'x86_64 = "linux_x64"' "$(TOOLS)"
    grep -q 'aarch64 = "linux_arm64"' "$(TOOLS)"
    grep -q 'target = target' "$(TOOLS)"
}

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
    # One installed formatter means one deterministic result; no second tool
    # silently rewrites Ruff's output.
    grep -q 'python = { "ruff_format" }' "$(TOOLS)"
    ! grep -q 'black' "$(TOOLS)"
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

@test "definition, references, type and help mappings are available after LSP attach" {
    for mapping in '"gd"' '"gD"' '"gr"' '"gi"' '"gy"' '"K"' \
                   '"<leader>lh"' '"<leader>ls"' '"<leader>lS"'; do
        grep -q "$mapping" "$(LSPCFG)"
    done
}

@test "LSP floats are visually separate from the editor" {
    grep -q 'NormalFloat.*bg = colors.one_bg' "$(OPTIONS)"
    grep -q 'FloatBorder.*fg = colors.blue' "$(OPTIONS)"
    grep -q 'NvThemeReload' "$(OPTIONS)"
    grep -q 'border = "rounded"' "$(LSPCFG)"
}

@test "hover is fully usable without a mouse" {
    grep -q 'set_hover_navigation' "$(LSPCFG)"
    grep -q '"K", return_to_source' "$(LSPCFG)"
    grep -q '"<Esc>", close_hover' "$(LSPCFG)"
}

@test "an empty LSP navigation result is explained instead of ignored" {
    grep -q 'no .* found' "$(LSPCFG)"
    grep -q 'compile_commands.json' "$(LSPCFG)"
    grep -q 'gi is mainly useful' "$(LSPCFG)"
    grep -q 'gy follows a symbol' "$(LSPCFG)"
}

@test "clangd trusts installed HIP compilers and warns about a moved CMake build" {
    grep -q '\-\-query-driver=' "$(TOOLS)"
    grep -Eq 'exepath[ (]+"hipcc"' "$(TOOLS)"
    grep -q 'CMAKE_HOME_DIRECTORY:INTERNAL=' "$(LSPCFG)"
    grep -q 'envup clangd sync' "$(LSPCFG)"
}

@test "clangd automatically consumes an envup-translated Docker database" {
    grep -q 'envup/clangd/index.tsv' "$(LSPCFG)"
    grep -q '\-\-compile-commands-dir=' "$(LSPCFG)"
    grep -q 'tools.clangd_cmd(drivers)' "$(LSPCFG)"
}

@test "LSP configuration loads when a real file is opened" {
    grep -q 'event = { "BufReadPre", "BufNewFile" }' "$(PLUGINS)"
}

@test "the final NvChad mapping layer keeps pane navigation tmux-aware" {
    for direction in Left Down Up Right; do
        grep -q "TmuxNavigate$direction" "$(MAPPINGS)"
    done
    grep -q '"<C-h>"' "$(MAPPINGS)"
    grep -q '"<C-j>"' "$(MAPPINGS)"
    grep -q '"<C-k>"' "$(MAPPINGS)"
    grep -q '"<C-l>"' "$(MAPPINGS)"
}
