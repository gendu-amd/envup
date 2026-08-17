-- Formatting.
--
-- The formatter list follows the language servers in configs/lspconfig.lua:
-- there is no point diagnosing C++ and then having no way to lay it out. Every
-- one of these is optional — conform skips a formatter that is not installed,
-- so a machine with only stylua behaves exactly as before.
--
-- `<leader>fm` formats on demand (NvChad's mapping). What is worth explaining
-- is when it happens *without* being asked; see format_on_save below.

local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    c = { "clang_format" },
    cpp = { "clang_format" },
    -- ruff over black: one binary, and it is what pyproject.toml files in this
    -- decade tend to configure. Falls through to black if ruff is absent.
    python = { "ruff_format", "black", stop_after_first = true },
    sh = { "shfmt" },
    bash = { "shfmt" },
    json = { "prettier" },
    yaml = { "prettier" },
    markdown = { "prettier" },
  },

  formatters = {
    -- Match the editor's own indentation rather than shfmt's tabs-by-default,
    -- so a formatted script does not look different from an unformatted one.
    shfmt = { prepend_args = { "-i", "4", "-ci" } },
  },
}

-- Format on save, but only where the project has said how it wants to be
-- formatted.
--
-- clang-format with no .clang-format uses LLVM style. Turned on unconditionally
-- that means the first save in someone else's repository reflows the whole file
-- to a style nobody there uses, and the diff is yours to explain. So the rule
-- is: a formatter runs on save when the project ships its config, and otherwise
-- waits for you to ask with `<leader>fm`.
--
-- Escape hatches, both directions:
--   :lua vim.b.disable_autoformat = true    this buffer
--   :lua vim.g.disable_autoformat = true    this session
--   :lua vim.g.envup_format_always = true   format on save regardless
local style_files = {
  clang_format = { ".clang-format", "_clang-format" },
  stylua = { ".stylua.toml", "stylua.toml" },
  ruff_format = { "ruff.toml", ".ruff.toml", "pyproject.toml" },
  black = { "pyproject.toml" },
  shfmt = { ".editorconfig" },
  prettier = { ".prettierrc", ".prettierrc.json", ".prettierrc.yaml", "prettier.config.js" },
}

local function project_has_style(bufnr)
  local ft = vim.bo[bufnr].filetype
  local dir = vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  if dir == "" or dir == nil then
    return false
  end
  for _, formatter in ipairs(options.formatters_by_ft[ft] or {}) do
    local names = style_files[formatter]
    if names and #vim.fs.find(names, { upward = true, path = dir, type = "file" }) > 0 then
      return true
    end
  end
  return false
end

options.format_on_save = function(bufnr)
  if vim.b[bufnr].disable_autoformat or vim.g.disable_autoformat then
    return nil
  end
  -- A file big enough to be opened in a stripped-down buffer is a file you are
  -- reading, not editing. See configs/bigfile.lua.
  if vim.b[bufnr].envup_bigfile then
    return nil
  end
  if not (vim.g.envup_format_always or project_has_style(bufnr)) then
    return nil
  end
  -- No lsp_format fallback: an LSP that formats on save is the same surprise
  -- this whole function exists to avoid, just from a different binary.
  return { timeout_ms = 1000, lsp_format = "never" }
end

return options
