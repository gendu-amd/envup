local tools = require "configs.tools"
local function budget(name, default)
  local value = tonumber(vim.env[name] or default)
  assert(value and value > 0 and value < math.huge and value == math.floor(value), name .. " must be a positive integer")
  return value
end

local git_timeout = math.min(budget("ENVUP_NET_TIMEOUT", 120), budget("ENVUP_NET_TIMEOUT_NVIM", 600))
local mirror = vim.env.ENVUP_GH_MIRROR
if mirror and mirror ~= "" and not tools.offline() then
  -- Changing Lazy's declared URL makes restore clean and reclone existing repositories.
  -- Git parameters redirect transport while preserving origin, including on older Git.
  local rule = "url." .. mirror:gsub("/+$", "") .. "/https://github.com/.insteadOf=https://github.com/"
  local quoted = "'" .. rule:gsub("'", "'\\''") .. "'"
  local previous = vim.env.GIT_CONFIG_PARAMETERS or ""
  if not previous:find(quoted, 1, true) then
    vim.env.GIT_CONFIG_PARAMETERS = previous == "" and quoted or previous .. " " .. quoted
  end
end

return {
  lockfile = tools.prepare_lock(),
  defaults = { lazy = true },
  install = { colorscheme = { "nvchad" }, missing = not tools.offline() },
  git = { timeout = git_timeout },
  checker = { enabled = false },

  ui = {
    icons = {
      ft = "",
      lazy = "󰂠 ",
      loaded = "",
      not_loaded = "",
    },
  },

  performance = {
    rtp = {
      disabled_plugins = {
        "2html_plugin",
        "tohtml",
        "getscript",
        "getscriptPlugin",
        "gzip",
        "logipat",
        "netrw",
        "netrwPlugin",
        "netrwSettings",
        "netrwFileHandlers",
        "matchit",
        "tar",
        "tarPlugin",
        "rrhelper",
        "spellfile_plugin",
        "vimball",
        "vimballPlugin",
        "zip",
        "zipPlugin",
        "tutor",
        "rplugin",
        "syntax",
        "synmenu",
        "optwin",
        "compiler",
        "bugreport",
        "ftplugin",
      },
    },
  },
}
