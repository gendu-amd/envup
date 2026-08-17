-- LSP config compatible with nvim 0.10 (legacy lspconfig.<server>.setup API).
-- We avoid `require("nvchad.configs.lspconfig").defaults()` because:
--   1. It only exists on the newer NvChad commits that depend on
--      vim.lsp.config (a nvim 0.11+ API).
--   2. Our NvChad pin (46b15ef in init.lua) only exposes
--      M.on_attach / M.capabilities / M.on_init, NOT defaults().
-- See plugins/init.lua and init.lua for the corresponding plugin pins.

-- Add Mason bin to PATH so LSP servers can be found
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin"
vim.env.PATH = mason_bin .. ":" .. vim.env.PATH

-- Reuse NvChad's LSP attach/capabilities/init (still exposed at this commit).
local nvlsp = require("nvchad.configs.lspconfig")
local lspconfig = require("lspconfig")

-- Setup each LSP server with shared NvChad attach/capabilities. Keep this
-- list in sync with mason-lspconfig's `ensure_installed` in plugins/init.lua.
local servers = { "clangd", "pyright", "lua_ls", "bashls" }
for _, server in ipairs(servers) do
  lspconfig[server].setup({
    on_attach = nvlsp.on_attach,
    capabilities = nvlsp.capabilities,
    on_init = nvlsp.on_init,
  })
end

-- Recognize .inc files as C++
vim.filetype.add({
  extension = {
    inc = "cpp",
    hpp = "cpp",
  },
})

-- Diagnostics you can actually read.
--
-- The virtual text at the end of the line is truncated to whatever fits, and a
-- clangd template error does not fit in a terminal — you get "no matching
-- function for call to" and then the screen edge. So: keep the inline hint
-- short and deliberate, and put the full text one keystroke away in a float.
vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = "●", source = "if_many" },
  float = { border = "rounded", source = "if_many", header = "", prefix = "" },
  severity_sort = true,
  underline = true,
  update_in_insert = false, -- errors that appear as you type are noise
})

-- vim.diagnostic.jump arrived in nvim 0.11 and deprecates goto_next/goto_prev.
-- This config still supports 0.10 (see the NvChad pin in init.lua), so pick
-- whichever exists rather than choosing a side.
local function diag_jump(count)
  return function()
    if vim.diagnostic.jump then
      vim.diagnostic.jump({ count = count, float = true })
    elseif count > 0 then
      vim.diagnostic.goto_next({ float = true })
    else
      vim.diagnostic.goto_prev({ float = true })
    end
  end
end

-- Additional LSP keymaps (when any LSP attaches)
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local opts = { buffer = args.buf, silent = true }
    vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
    vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
    vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
    vim.keymap.set("n", "gi", vim.lsp.buf.implementation, opts)
    vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
    vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
    vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)

    -- Moving between problems, and reading the one you landed on. `[d`/`]d`
    -- are vim's own diagnostic motions; the float opens on arrival so the
    -- jump and the message are one action.
    vim.keymap.set("n", "]d", diag_jump(1), opts)
    vim.keymap.set("n", "[d", diag_jump(-1), opts)
    -- `df`, not `d`: NvChad already binds `<leader>ds` (every problem in the
    -- file, in the location list), and a bare `<leader>d` would make you wait
    -- out timeoutlen every time you reached for it.
    vim.keymap.set("n", "<leader>df", vim.diagnostic.open_float, opts)
  end,
})
