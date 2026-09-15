local tools = require "configs.tools"

return {
  {
    "stevearc/conform.nvim",
    -- Lazy loads before the first save so format_on_save receives the event.
    event = "BufWritePre",
    cmd = "ConformInfo",
    opts = require "configs.conform",
  },

  -- v1 retains Nvim 0.10 support; it must load before lspconfig.
  {
    "williamboman/mason-lspconfig.nvim",
    version = "^1",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = tools.lsp_servers,
        -- Avoid racing the explicit lspconfig setup during first install.
        automatic_installation = false,
      })
    end,
  },

  {
    "neovim/nvim-lspconfig",
    -- v1 retains the legacy setup API required by the pinned NvChad commit.
    version = "^1",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "williamboman/mason-lspconfig.nvim" },
    config = function()
      require "configs.lspconfig"
    end,
  },

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

  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    opts = {},
  },

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

  -- Last Telescope release supporting Nvim 0.10.
  {
    "nvim-telescope/telescope.nvim",
    tag = "0.1.8",
  },

  -- master retains the configs API used by the pinned NvChad release.
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

  {
    "christoomey/vim-tmux-navigator",
    -- mappings.lua reapplies final normal-mode bindings after NvChad.
    lazy = false,
  },
}
