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
  end,
})
