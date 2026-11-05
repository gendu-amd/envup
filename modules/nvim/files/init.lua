vim.g.base46_cache = vim.fn.stdpath "data" .. "/base46/"
vim.g.mapleader = " "

-- Host and private overrides load last; errors do not abort startup.
local function load_overrides()
  require "configs.clipboard"
  local _cfg = vim.fn.stdpath "config"
  local _host = (vim.uv.os_gethostname() or ""):gsub("%..*$", "")
  if _host ~= "" then
    pcall(dofile, _cfg .. "/hosts/" .. _host .. ".lua")
  end
  pcall(dofile, _cfg .. "/local.lua")
end

local tools = require "configs.tools"
if not tools.plugins_enabled() then
  load_overrides()
  return
end

local lazypath = vim.fn.stdpath "data" .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazypath .. "/lua/lazy/init.lua") then
  vim.api.nvim_echo({
    { tools.offline() and "[envup] offline: lazy.nvim missing at " or "[envup] lazy.nvim missing at ", "WarningMsg" },
    { lazypath, "Normal" },
    { " — using core editing; run: envup install nvim when online", "Normal" },
  }, true, {})
  load_overrides()
  return
end

if tools.offline() then
  local ok, missing = pcall(tools.missing_plugins)
  if not ok then missing = { "cache check failed: " .. tostring(missing) } end
  if #missing > 0 then
    vim.api.nvim_echo({
      { "[envup] offline: cached plugins incomplete: " .. table.concat(missing, ", "), "WarningMsg" },
      { "\nUsing core editing; run envup install nvim when online.", "Normal" },
    }, true, {})
    load_overrides()
    return
  end
end

vim.opt.rtp:prepend(lazypath)

local lazy_config = require "configs.lazy"

require("lazy").setup({
  -- The shallow stable-tag bootstrap has detached HEAD and no origin/HEAD.
  { "folke/lazy.nvim", branch = "main" },
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
require("configs.session").setup()
require("configs.bigfile").setup()

vim.schedule(function()
  require "mappings"
end)

load_overrides()
