-- LSP config compatible with nvim 0.10 (legacy lspconfig.<server>.setup API).
-- We avoid `require("nvchad.configs.lspconfig").defaults()` because:
--   1. It only exists on the newer NvChad commits that depend on
--      vim.lsp.config (a nvim 0.11+ API).
--   2. Our NvChad pin (46b15ef in init.lua) only exposes
--      M.on_attach / M.capabilities / M.on_init, NOT defaults().
-- See plugins/init.lua and init.lua for the corresponding plugin pins.

local tools = require "configs.tools"
tools.prepend_mason_bin()

-- Reuse NvChad's LSP attach/capabilities/init (still exposed at this commit).
local nvlsp = require "nvchad.configs.lspconfig"
local lspconfig = require "lspconfig"

local function envup_compile_db(root)
  local index = vim.fn.stdpath "cache" .. "/envup/clangd/index.tsv"
  if vim.fn.filereadable(index) ~= 1 then
    return nil
  end
  local actual = vim.uv.fs_realpath(root) or vim.fs.normalize(root)
  for _, line in ipairs(vim.fn.readfile(index)) do
    local fields = vim.split(line, "\t", { plain = true })
    local recorded = fields[1] and (vim.uv.fs_realpath(fields[1]) or vim.fs.normalize(fields[1]))
    if recorded == actual and fields[2] and vim.uv.fs_stat(fields[2]) then
      local drivers = fields[3] and fields[3] ~= "" and vim.split(fields[3], ",", { plain = true }) or {}
      local stale = false
      if fields[6] and fields[7] and fields[7] ~= "" then
        local source_stat = vim.uv.fs_stat(fields[6])
        stale = not source_stat or tostring(source_stat.mtime.sec) ~= fields[7]
      end
      return fields[2], drivers, stale
    end
  end
end

local function find_compile_db(root)
  local cached = envup_compile_db(root)
  if cached then
    return cached
  end
  local config = root .. "/.clangd"
  if vim.fn.filereadable(config) == 1 then
    for _, line in ipairs(vim.fn.readfile(config)) do
      local dir = line:match "^%s*CompilationDatabase:%s*(.-)%s*$"
      if dir then
        dir = dir:gsub("^([\"'])(.*)%1$", "%2")
        if dir == "None" then
          return nil
        end
        if dir ~= "Ancestors" then
          if dir:sub(1, 1) ~= "/" then
            dir = root .. "/" .. dir
          end
          return vim.fs.normalize(dir .. "/compile_commands.json")
        end
      end
    end
  end

  for _, path in ipairs { root .. "/compile_commands.json", root .. "/build/compile_commands.json" } do
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

local function warn_stale_cmake_database(client)
  if client.name ~= "clangd" then
    return
  end
  local root = client.config.root_dir
  if not root or root == "" then
    return
  end

  if envup_compile_db(root) then
    return
  end

  local database = find_compile_db(root)
  if not database or not vim.uv.fs_stat(database) then
    return
  end
  local cache = vim.fs.dirname(database) .. "/CMakeCache.txt"
  if not vim.uv.fs_stat(cache) then
    return
  end

  local ok, lines = pcall(vim.fn.readfile, cache)
  if not ok then
    return
  end
  for _, line in ipairs(lines) do
    local configured_root = line:match "^CMAKE_HOME_DIRECTORY:INTERNAL=(.+)$"
    if configured_root then
      local actual = vim.uv.fs_realpath(root) or vim.fs.normalize(root)
      local configured = vim.uv.fs_realpath(configured_root)
      if not configured and vim.fs.normalize(configured_root) ~= actual then
        vim.notify_once(
          (
            "clangd: %s was generated for missing source tree %s, not %s. "
            .. "Navigation will be incomplete; run `envup clangd sync` in the project, then :LspRestart."
          ):format(database, configured_root, root),
          vim.log.levels.WARN
        )
      end
      return
    end
  end
end

local function client_for(bufnr, method)
  for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
    if client.supports_method(method) then
      return client
    end
  end
end

local function lsp_request(method, label, no_result_hint, handler_options, after_handler)
  return function()
    local bufnr = vim.api.nvim_get_current_buf()
    local source_win = vim.api.nvim_get_current_win()
    local client = client_for(bufnr, method)
    if not client then
      vim.notify("LSP: no attached server supports " .. label, vim.log.levels.WARN)
      return
    end

    local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
    if method == "textDocument/references" then
      params.context = { includeDeclaration = true }
    end
    local sent = client.request(method, params, function(err, result, ctx)
      if err then
        vim.notify(("LSP %s failed: %s"):format(label, err.message or tostring(err)), vim.log.levels.ERROR)
        return
      end
      if result == nil or (type(result) == "table" and vim.tbl_isempty(result)) then
        local suffix = no_result_hint and (" " .. no_result_hint) or ""
        vim.notify("LSP: no " .. label .. " found." .. suffix, vim.log.levels.WARN)
        return
      end
      local result_buf, result_win = vim.lsp.handlers[method](nil, result, ctx, handler_options or {})
      if after_handler then
        after_handler(result_buf, result_win, source_win)
      end
    end, bufnr)
    if not sent then
      vim.notify("LSP: could not request " .. label, vim.log.levels.ERROR)
    end
  end
end

local function set_hover_navigation(float_buf, float_win, source_win)
  if not float_buf or not float_win or not vim.api.nvim_win_is_valid(float_win) then
    return
  end

  local function return_to_source()
    if vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    else
      vim.cmd "wincmd p"
    end
  end
  local function close_hover()
    if vim.api.nvim_win_is_valid(float_win) then
      vim.api.nvim_win_close(float_win, true)
    end
    if vim.api.nvim_win_is_valid(source_win) then
      vim.api.nvim_set_current_win(source_win)
    end
  end

  vim.keymap.set("n", "K", return_to_source, { buffer = float_buf, silent = true, desc = "Return from hover" })
  vim.keymap.set("n", "<Esc>", close_hover, { buffer = float_buf, silent = true, desc = "Close hover" })
end

-- Recognize .inc files as C++
vim.filetype.add {
  extension = {
    inc = "cpp",
    hpp = "cpp",
  },
}

-- Diagnostics you can actually read.
--
-- The virtual text at the end of the line is truncated to whatever fits, and a
-- clangd template error does not fit in a terminal — you get "no matching
-- function for call to" and then the screen edge. So: keep the inline hint
-- short and deliberate, and put the full text one keystroke away in a float.
vim.diagnostic.config {
  virtual_text = { spacing = 2, prefix = "●", source = "if_many" },
  float = { border = "rounded", source = "if_many", header = "", prefix = "" },
  severity_sort = true,
  underline = true,
  update_in_insert = false, -- errors that appear as you type are noise
}

-- vim.diagnostic.jump arrived in nvim 0.11 and deprecates goto_next/goto_prev.
-- This config still supports 0.10 (see the NvChad pin in init.lua), so pick
-- whichever exists rather than choosing a side.
local function diag_jump(count)
  return function()
    if vim.diagnostic.jump then
      vim.diagnostic.jump { count = count, float = true }
    elseif count > 0 then
      vim.diagnostic.goto_next { float = true }
    else
      vim.diagnostic.goto_prev { float = true }
    end
  end
end

-- Run NvChad's setup first, then install envup's final mappings. An LspAttach
-- autocmd runs too early on this NvChad version: its on_attach subsequently
-- replaces gd/K, making the nicer UI and the no-result explanation disappear.
local function on_attach(client, bufnr)
  nvlsp.on_attach(client, bufnr)
  warn_stale_cmake_database(client)

  local function map(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = bufnr, silent = true, desc = desc })
  end

  map(
    "gd",
    lsp_request(
      "textDocument/definition",
      "definition",
      "For C/C++, verify compile_commands.json; for a declaration, try gD."
    ),
    "LSP: Go to definition"
  )
  map("gD", lsp_request("textDocument/declaration", "declaration"), "LSP: Go to declaration")
  map("gr", lsp_request("textDocument/references", "references"), "LSP: Find references")
  map(
    "gi",
    lsp_request(
      "textDocument/implementation",
      "implementation",
      "gi is mainly useful for interfaces and virtual methods."
    ),
    "LSP: Go to implementation"
  )
  map(
    "gy",
    lsp_request(
      "textDocument/typeDefinition",
      "type definition",
      "gy follows a symbol's type; use gd/gD for functions and variables."
    ),
    "LSP: Go to type definition"
  )
  map(
    "K",
    lsp_request(
      "textDocument/hover",
      "hover information",
      nil,
      { border = "rounded", max_width = 100, max_height = 30 },
      set_hover_navigation
    ),
    "LSP: Hover documentation"
  )
  map("<leader>rn", vim.lsp.buf.rename, "LSP: Rename")
  map("<leader>ca", vim.lsp.buf.code_action, "LSP: Code action")
  map(
    "<leader>lh",
    lsp_request(
      "textDocument/signatureHelp",
      "signature help",
      nil,
      { border = "rounded", max_width = 100, max_height = 30 }
    ),
    "LSP: Signature help"
  )
  map("<leader>ls", vim.lsp.buf.document_symbol, "LSP: Document symbols")
  map("<leader>lS", vim.lsp.buf.workspace_symbol, "LSP: Workspace symbols")

  -- Moving between problems, and reading the one you landed on. `[d`/`]d`
  -- are vim's own diagnostic motions; the float opens on arrival so the
  -- jump and the message are one action.
  map("]d", diag_jump(1), "Diagnostic: Next")
  map("[d", diag_jump(-1), "Diagnostic: Previous")
  -- `df`, not `d`: NvChad already binds `<leader>ds` (every problem in the
  -- file, in the location list), and a bare `<leader>d` would make you wait
  -- out timeoutlen every time you reached for it.
  map("<leader>df", vim.diagnostic.open_float, "Diagnostic: Show message")
end

-- Setup each server from the same inventory the installer uses. Server-specific
-- settings are merged over the shared NvChad defaults.
for _, server in ipairs(tools.lsp_servers) do
  local options = vim.tbl_deep_extend("force", {
    on_attach = on_attach,
    capabilities = nvlsp.capabilities,
    on_init = nvlsp.on_init,
  }, tools.lsp_settings[server] or {})
  if server == "clangd" then
    local inherited = options.on_new_config
    options.on_new_config = function(config, root)
      if inherited then
        inherited(config, root)
      end
      local database, drivers, stale = envup_compile_db(root)
      if database then
        config.cmd = tools.clangd_cmd(drivers)
        config.cmd[#config.cmd + 1] = "--compile-commands-dir=" .. vim.fs.dirname(database)
        if stale then
          vim.schedule(function()
            vim.notify_once(
              "clangd: Docker compile_commands.json changed; run `envup clangd sync`, then :LspRestart.",
              vim.log.levels.WARN
            )
          end)
        end
      end
    end
  end
  lspconfig[server].setup(options)
end
