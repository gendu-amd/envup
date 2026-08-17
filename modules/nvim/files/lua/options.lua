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

-- Undo that outlives the session. Reopen a file tomorrow and `u` still walks
-- back through yesterday's edits — which on a server you reach over SSH is the
-- difference between a dropped connection being an annoyance and being lost
-- work. History goes to stdpath("state")/undo (nvim creates it), keyed by the
-- file's full path, so a home directory shared over NFS does not mix machines
-- up. Excluded for big files; see configs/bigfile.lua.
o.undofile = true
o.undolevels = 10000
