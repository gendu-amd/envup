require "nvchad.mappings"

-- add yours here

local map = vim.keymap.set

-- Keep vim's default `;` (= repeat last f/F/t/T motion). The NvChad starter
-- template ships `map("n", ";", ":")` to "save a shift key", but that breaks
-- the default motion-repeat behaviour, which is more useful in practice.

map("i", "jk", "<ESC>")

-- NvChad also maps these to plain <C-w>h/j/k/l. Put the tmux-aware commands
-- in the final user mapping layer so an empty `nvim` startup and a file-backed
-- buffer behave the same: move through nvim splits, then cross the tmux pane
-- boundary when there is no split left in that direction.
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Navigate left (nvim/tmux)" })
map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "Navigate down (nvim/tmux)" })
map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "Navigate up (nvim/tmux)" })
map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "Navigate right (nvim/tmux)" })

-- Visual block mode alias.
-- The standard vim key for visual-block is <C-v>, but most GUI/embedded
-- terminals (VSCode/Cursor integrated terminal, Windows Terminal, MobaXterm,
-- ...) intercept Ctrl+V at the OS level to paste from the system clipboard,
-- so the keystroke never reaches nvim. <C-q> is vim's official terminal-safe
-- alternative — same effect, no hijacking.
map({ "n", "v" }, "<C-q>", "<C-v>", { desc = "visual block (terminal-safe alt for <C-v>)" })

-- map({ "n", "i", "v" }, "<C-s>", "<cmd> w <cr>")

-- ========================================
-- Gitsigns keymaps
-- ========================================
map("n", "]c", function()
  if vim.wo.diff then return "]c" end
  vim.schedule(function() require("gitsigns").next_hunk() end)
  return "<Ignore>"
end, { expr = true, desc = "Git: Next hunk" })

map("n", "[c", function()
  if vim.wo.diff then return "[c" end
  vim.schedule(function() require("gitsigns").prev_hunk() end)
  return "<Ignore>"
end, { expr = true, desc = "Git: Prev hunk" })

map("n", "<leader>ph", function() require("gitsigns").preview_hunk() end, { desc = "Git: Preview hunk" })
map("n", "<leader>rh", function() require("gitsigns").reset_hunk() end, { desc = "Git: Reset hunk" })
map("n", "<leader>sh", function() require("gitsigns").stage_hunk() end, { desc = "Git: Stage hunk" })
map("n", "<leader>uh", function() require("gitsigns").undo_stage_hunk() end, { desc = "Git: Undo stage hunk" })
map("n", "<leader>gb", function() require("gitsigns").blame_line({ full = true }) end, { desc = "Git: Blame line" })
map("n", "<leader>td", function() require("gitsigns").toggle_deleted() end, { desc = "Git: Toggle deleted" })
map("n", "<leader>rB", function() require("gitsigns").reset_buffer() end, { desc = "Git: Reset buffer" })
