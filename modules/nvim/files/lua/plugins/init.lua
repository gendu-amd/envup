local tools = require "configs.tools"

return {
  {
    "stevearc/conform.nvim",
    -- Lazy loads before the first save so format_on_save receives the event.
    event = "BufWritePre",
    cmd = "ConformInfo",
    -- Replace NvChad's default Lua formatter when Lua is not selected.
    opts = function()
      return require "configs.conform"
    end,
  },

  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      local mirror = vim.env.ENVUP_GH_MIRROR
      local template = opts.github and opts.github.download_url_template
        or "https://github.com/%s/releases/download/%s/%s"
      if mirror and mirror ~= "" and not tools.offline() and template:match("^https?://github%.com/") then
        opts.github = opts.github or {}
        -- Mason formats this template later; percent escapes in a mirror URL are literals.
        opts.github.download_url_template = mirror:gsub("/+$", ""):gsub("%%", "%%%%") .. "/" .. template
      end
    end,
  },

  -- v1 retains Nvim 0.10 support; it must load before lspconfig.
  {
    "williamboman/mason-lspconfig.nvim",
    version = "^1",
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        -- envup's explicit install step owns the budget and verifies runnable tools.
        ensure_installed = {},
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
    -- Download and compile in envup's synchronous step, not during startup or restore.
    build = false,
    opts = function(_, opts)
      opts.ensure_installed = {}
      opts.auto_install = false
    end,
  },

  {
    "christoomey/vim-tmux-navigator",
    -- mappings.lua reapplies final normal-mode bindings after NvChad.
    lazy = false,
  },
}
