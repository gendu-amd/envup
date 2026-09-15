vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath) then
  local repo = "https://github.com/folke/lazy.nvim.git"
  -- Honor envup's GitHub mirror during interactive bootstrap.
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

require("lazy").setup({
  {
    "NvChad/NvChad",
    lazy = false,
    -- Last v2.5 commit before NvChad moved to the Nvim 0.11-only LSP API.
    commit = "46b15ef1b9d10a83ab7df26b14f474d15c01e770",
    import = "nvchad.plugins",
  },

  { import = "plugins" },
}, lazy_config)

dofile(vim.g.base46_cache .. "defaults")
dofile(vim.g.base46_cache .. "statusline")

require "options"
require "autocmds"
require "configs.clipboard"
require("configs.session").setup()
require("configs.bigfile").setup()

vim.schedule(function()
  require "mappings"
end)

-- Host and private overrides load last; errors do not abort startup.
local _cfg = vim.fn.stdpath "config"
local _host = (vim.uv.os_gethostname() or ""):gsub("%..*$", "")
if _host ~= "" then
  pcall(dofile, _cfg .. "/hosts/" .. _host .. ".lua")
end
pcall(dofile, _cfg .. "/local.lua")
