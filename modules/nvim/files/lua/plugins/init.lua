return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- Mason-lspconfig: auto-install LSP servers
  -- Must load BEFORE lspconfig to ensure servers are installed
  --
  -- IMPORTANT: pinned to v1.x because v2.0 dropped support for the wrapped
  -- LSP enable path and now calls vim.lsp.enable directly (added in nvim
  -- 0.11). On nvim 0.10 / older glibc systems where you cannot upgrade
  -- nvim past 0.10 (newer AppImages need glibc 2.33+), v2 fails with
  --   automatic_enable.lua:47: attempt to call field 'enable' (a nil value)
  -- Bump to "^2" once you're on nvim >= 0.11.
  {
    "williamboman/mason-lspconfig.nvim",
    version = "^1",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "clangd", "pyright", "lua_ls", "bashls" },
        -- lspconfig.setup() runs for the same servers in configs/lspconfig.lua;
        -- leaving automatic_installation on races ensure_installed →
        -- "Package is already installing" (clangd, …) on first launch.
        automatic_installation = false,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    -- v2/v3 of nvim-lspconfig dropped the legacy `lspconfig.<server>.setup{}`
    -- table interface that NvChad's pinned commit (and our configs/lspconfig)
    -- relies on. v1.x retains it. Pair this with the NvChad commit pin above.
    -- Bump once you're on nvim >= 0.11 AND moved off the old API.
    version = "^1",
    dependencies = { "williamboman/mason-lspconfig.nvim" },
    config = function()
      require "configs.lspconfig"
    end,
  },

  -- ========================================
  -- Additional Plugins
  -- ========================================

  -- 1. todo-comments: Highlight TODO/FIXME/HACK/NOTE comments
  {
    "folke/todo-comments.nvim",
    event = "BufRead",
    dependencies = { "nvim-lua/plenary.nvim" },
    opts = {},
    keys = {
      { "]t", function() require("todo-comments").jump_next() end, desc = "Next TODO" },
      { "[t", function() require("todo-comments").jump_prev() end, desc = "Prev TODO" },
      { "<leader>ft", "<cmd>TodoTelescope<cr>", desc = "Find TODOs" },
    },
  },

  -- 2. nvim-surround: Quickly add/change/delete surrounding pairs
  --    ysiw" → add quotes: word → "word"
  --    cs"'  → change quotes: "word" → 'word'
  --    ds"   → delete quotes: "word" → word
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    opts = {},
  },

  -- 3. interestingwords: Multi-color word highlighting
  --    <leader>k → highlight current word (auto-assign color)
  --    <leader>K → clear all highlights
  --    n/N → jump to next/prev highlight
  {
    "Mr-LLLLL/interestingwords.nvim",
    event = "VeryLazy",
    opts = {
      colors = { "#ff5555", "#50fa7b", "#f1fa8c", "#bd93f9", "#ff79c6", "#8be9fd" },
      search_count = true,
      navigation = true,
    },
    keys = {
      { "<leader>k", function() require("interestingwords").mark_word() end, desc = "Highlight word" },
      { "<leader>K", function() require("interestingwords").mark_clear() end, desc = "Clear highlights" },
    },
  },

  -- Buffer tabs are handled by NvChad's built-in tabufline (no extra plugin).
  -- Switch buffers with <Tab>/<S-Tab>, close with <leader>x, and jump among
  -- many open files with <leader>fb (Telescope buffers) — which scales far
  -- better than a tab bar once you have more files than fit on one row.

  -- Telescope: fuzzy finder (provides :Telescope and is wired to many NvChad
  -- default keymaps such as <leader>ff / <leader>fw / <leader>fz).
  --
  -- IMPORTANT: pin to tag 0.1.8 — the last release that supports Neovim 0.10.
  -- After commit e6cdb4d ("feat!: require Nvim 0.11 and drop compat shims",
  -- 2026-04, included in v0.1.9 / v0.2.x), telescope hard-requires nvim
  -- 0.11.7+ and silently fails to register the :Telescope command on 0.10:
  --   E492: Not an editor command: Telescope ...
  -- Bump only after upgrading to nvim >= 0.11.
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
  },

  -- 4. treesitter: Better syntax highlighting
  --
  -- IMPORTANT: pin to `master` branch.
  -- nvim-treesitter's `main` branch was refactored in commit 692b051b
  -- ("feat!: drop modules, general refactor and cleanup", 2025-05-12),
  -- removing the `nvim-treesitter.configs` module that NvChad's pinned
  -- commit (and most other distros) still call. Without this pin, lazy.nvim
  -- pulls main HEAD and you get:
  --   NvChad/lua/nvchad/plugins/init.lua:166: module 'nvim-treesitter.configs' not found
  -- The `master` branch is archived but kept stable for legacy users.
  -- Bump only when NvChad (and friends) migrate to the new main API.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "master",
    opts = {
      ensure_installed = {
        "vim", "lua", "vimdoc", "html", "css",
        "python", "cpp", "c", "bash", "json", "yaml", "markdown",
      },
    },
  },

  -- 5. vim-tmux-navigator: Seamless Ctrl+h/j/k/l navigation between nvim and tmux
  {
    "christoomey/vim-tmux-navigator",
    lazy = false,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
    },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate Left" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate Down" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate Up" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate Right" },
    },
  },
}
