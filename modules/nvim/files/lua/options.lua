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

-- NvChad's onedark NormalFloat is only three RGB levels away from the editor
-- background, so LSP hover/signature text looks as if it were drawn directly
-- over the buffer. Apply this after the cached theme and after every theme
-- reload; putting it only in chadrc would not update an already-built cache.
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

-- Undo that outlives the session. Reopen a file tomorrow and `u` still walks
-- back through yesterday's edits — which on a server you reach over SSH is the
-- difference between a dropped connection being an annoyance and being lost
-- work. History goes to stdpath("state")/undo (nvim creates it), keyed by the
-- file's full path, so a home directory shared over NFS does not mix machines
-- up. Excluded for big files; see configs/bigfile.lua.
o.undofile = true
o.undolevels = 10000
