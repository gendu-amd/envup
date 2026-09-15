require "nvchad.options"

local o = vim.o

-- Line numbers
o.number = true
o.relativenumber = false

-- Cursor
o.cursorline = true

-- Indentation
o.tabstop = 4
o.shiftwidth = 4
o.expandtab = true

-- Search
o.ignorecase = true
o.smartcase = true

-- UI
o.scrolloff = 8

-- Keep floating windows distinct after initial load and theme reloads.
local function set_float_highlights()
  local ok, base46 = pcall(require, "base46")
  if not ok then
    return
  end
  local colors = base46.get_theme_tb "base_30"
  vim.api.nvim_set_hl(0, "NormalFloat", { bg = colors.one_bg })
  vim.api.nvim_set_hl(0, "FloatBorder", { fg = colors.blue, bg = colors.one_bg })
  vim.api.nvim_set_hl(0, "FloatTitle", { fg = colors.black, bg = colors.blue, bold = true })
end
set_float_highlights()
vim.api.nvim_create_autocmd("User", { pattern = "NvThemeReload", callback = set_float_highlights })

-- Persistent undo is disabled per-buffer by the big-file guard.
o.undofile = true
o.undolevels = 10000
