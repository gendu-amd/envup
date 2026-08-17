vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- bootstrap lazy and all plugins
local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  -- Honor envup's mirror/proxy prefix (ENVUP_GH_MIRROR, e.g. https://ghproxy.com)
  -- so a first interactive launch behind a GitHub-blocked network still works.
  local mirror = os.getenv("ENVUP_GH_MIRROR")
  if mirror and #mirror > 0 then
    repo = mirror:gsub("/+$", "") .. "/" .. repo
  end
  vim.fn.system { "git", "clone", "--filter=blob:none", repo, "--branch=stable", lazypath }
  if vim.v.shell_error ~= 0 or not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
    vim.api.nvim_echo({
      { "[envup] lazy.nvim bootstrap failed (git clone). ", "ErrorMsg" },
      { "Run: git clone --filter=blob:none https://github.com/folke/lazy.nvim.git --branch=stable ", "Normal" },
      { lazypath, "Normal" },
      { "\nOr: envup install nvim", "Normal" },
    }, true, {})
    return
  end
end

if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
  vim.api.nvim_echo({
    { "[envup] lazy.nvim missing at ", "ErrorMsg" },
    { lazypath, "Normal" },
    { " — run: envup install nvim", "Normal" },
  }, true, {})
  return
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

-- load plugins
require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    -- IMPORTANT: pin to a specific commit, NOT branch = "v2.5".
    -- The "v2.5" branch is treated as a rolling stable line by NvChad
    -- maintainers and has since migrated to the nvim 0.11+ vim.lsp.config /
    -- vim.lsp.enable API (commit 1b220e9 "refactor: migrate to
    -- vim.lsp.config/enable"). On systems where you cannot upgrade nvim past
    -- 0.10 (e.g. glibc < 2.33 prevents the official 0.11+ AppImage), branch
    -- HEAD breaks with:
    --   nvchad/configs/lspconfig.lua:81: attempt to call field 'config' (a nil value)
    -- 46b15ef is the last commit on v2.5 BEFORE that migration; it stays
    -- on the legacy `lspconfig.<server>.setup{}` API and works on nvim 0.10.
    -- Bump once you're on nvim >= 0.11.
    commit = "46b15ef1b9d10a83ab7df26b14f474d15c01e770",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

-- load theme
dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"
-- After options: NvChad sets clipboard=unnamedplus, and this decides where that
-- actually goes on a machine with no clipboard tool. See configs/clipboard.lua.
require "configs.clipboard"
-- Writes Session.vim while you work, so a tmux pane that a reboot took down
-- comes back with your files in it. No-op outside tmux. See configs/session.lua.
require("configs.session").setup()

vim.schedule(function()
  require "mappings"
end)

-- Per-machine overrides, in two layers. Both load LAST so either can override
-- plugins/theme/options/mappings, and pcall keeps a missing file or a typo in
-- one from taking nvim's startup down with it.
--
--   hosts/<hostname>.lua  IN the repo: committed, so it syncs to your other
--                         machines and survives a rebuild — and stays separate
--                         from them on a home directory shared over NFS.
--                         Start from hosts/example.lua.template.
--   local.lua             NOT in the repo: private to this machine, wins.
local _cfg = vim.fn.stdpath "config"
local _host = (vim.uv.os_gethostname() or ""):gsub("%..*$", "")
if _host ~= "" then
  pcall(dofile, _cfg .. "/hosts/" .. _host .. ".lua")
end
pcall(dofile, _cfg .. "/local.lua")
