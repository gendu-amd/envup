local M = {}
function M.offline()
  return vim.env.ENVUP_NET == "offline" or vim.env.ENVUP_OFFLINE == "1"
end
local default_languages = {
  "vim", "lua", "vimdoc", "html", "css", "python", "cpp", "c", "bash", "json", "yaml", "markdown",
}

-- Health checks read data only; private Lua overrides may have startup effects.
local function read_selection()
  local path = vim.fn.stdpath "config" .. "/envup.json"
  local stat, err, code = vim.uv.fs_stat(path)
  if not stat then
    assert(code == "ENOENT" and not vim.uv.fs_lstat(path), "cannot read envup.json: " .. tostring(err))
    return {}
  end
  assert(stat.type == "file", "envup.json must be a JSON file")
  local text = table.concat(vim.fn.readfile(path), "\n")
  assert(text:match "^%s*{", "envup.json must contain a JSON object")
  local config = vim.json.decode(text)
  for key in pairs(config) do
    assert(key == "plugins" or key == "languages", "unknown envup.json option: " .. tostring(key))
  end
  assert(config.plugins == nil or type(config.plugins) == "boolean", "envup.json plugins must be boolean")
  if config.languages ~= nil then
    assert(type(config.languages) == "table" and vim.islist(config.languages), "envup.json languages must be an array")
    for _, language in ipairs(config.languages) do
      assert(vim.tbl_contains(default_languages, language), "unsupported envup.json language: " .. tostring(language))
    end
  end
  return config
end

local selection = read_selection()
function M.plugins_enabled()
  return selection.plugins ~= false
end

function M.prepare_lock(reset)
  local path = vim.fn.stdpath "state" .. "/lazy-lock.json"
  local stat = vim.uv.fs_lstat(path)
  assert(not stat or stat.type == "file", "Lazy state lock must be a regular file")
  local valid = false
  if vim.uv.fs_stat(path) then
    valid = pcall(function() vim.json.decode(table.concat(vim.fn.readfile(path), "\n")) end)
  end
  if reset or not valid then
    local source = vim.fn.stdpath "config" .. "/lazy-lock.json"
    local lines = vim.fn.readfile(source)
    local text = table.concat(lines, "\n")
    assert(text:match "^%s*{", "pinned Lazy lock must be a JSON object")
    vim.json.decode(text)
    vim.fn.mkdir(vim.fn.stdpath "state", "p")
    local tmp = path .. "." .. vim.fn.getpid()
    assert(vim.fn.writefile(lines, tmp) == 0, "cannot stage Lazy state lock")
    local ok, err = vim.uv.fs_rename(tmp, path)
    if not ok then vim.uv.fs_unlink(tmp); error(err) end
  end
  return path
end

local selected = {}
for _, language in ipairs(selection.languages or default_languages) do selected[language] = true end
local function wants(languages)
  for _, language in ipairs(languages) do
    if selected[language] then return true end
  end
  return false
end

-- One inventory drives installation, LSP setup and formatting. Keep Mason's
-- package name beside the executable it must leave behind: an install only
-- counts when the command Neovim will call is actually runnable.
M.mason_tools = {
  { package = "clangd", executable = "clangd", probe = { "clangd", "--version" }, languages = { "c", "cpp" }, server = "clangd" },
  { package = "pyright", executable = "pyright-langserver", probe = { "pyright", "--version" }, languages = { "python" }, server = "pyright" },
  {
    package = "lua-language-server",
    executable = "lua-language-server",
    probe = { "lua-language-server", "--version" },
    languages = { "lua" }, server = "lua_ls",
  },
  {
    package = "bash-language-server",
    executable = "bash-language-server",
    probe = { "bash-language-server", "--version" },
    languages = { "bash" }, server = "bashls",
  },
  { package = "clang-format", executable = "clang-format", probe = { "clang-format", "--version" }, languages = { "c", "cpp" } },
  { package = "stylua", executable = "stylua", probe = { "stylua", "--version" }, portable = true, languages = { "lua" } },
  { package = "ruff", executable = "ruff", probe = { "ruff", "--version" }, languages = { "python" } },
  { package = "shfmt", executable = "shfmt", probe = { "shfmt", "--version" }, languages = { "bash" } },
  { package = "prettier", executable = "prettier", probe = { "prettier", "--version" }, languages = { "json", "yaml", "markdown" } },
}

local inventory = M.mason_tools
M.mason_tools, M.lsp_servers, M.treesitter_parsers = {}, {}, {}
for _, tool in ipairs(inventory) do
  if wants(tool.languages) then
    M.mason_tools[#M.mason_tools + 1] = tool
    if tool.server then M.lsp_servers[#M.lsp_servers + 1] = tool.server end
  end
end
for _, language in ipairs(default_languages) do
  if selected[language] then M.treesitter_parsers[#M.treesitter_parsers + 1] = language end
end

local function clangd_cmd(extra_drivers)
  local cmd = { "clangd", "--background-index", "--clang-tidy", "--completion-style=detailed" }
  local drivers, seen = {}, {}

  local function add(path)
    if not path or path == "" or seen[path] or vim.fn.executable(path) ~= 1 then
      return
    end
    seen[path] = true
    drivers[#drivers + 1] = path
  end

  -- clangd intentionally refuses to execute arbitrary compilers named by a
  -- project's compile database. Trust only compilers already installed on the
  -- user's PATH, plus the ROCm clang beside a real hipcc. This is what lets a
  -- standalone/Mason clangd discover HIP's builtin headers and target flags
  -- without allowing a repository to make it execute an untrusted wrapper.
  for _, name in ipairs { "cc", "c++", "gcc", "g++", "clang", "clang++", "hipcc" } do
    local path = vim.fn.exepath(name)
    add(path)
    add(path ~= "" and vim.uv.fs_realpath(path) or nil)
  end

  local hipcc = vim.fn.exepath "hipcc"
  local real_hipcc = hipcc ~= "" and (vim.uv.fs_realpath(hipcc) or hipcc) or nil
  if real_hipcc then
    local rocm = vim.fn.fnamemodify(real_hipcc, ":h:h")
    add(rocm .. "/bin/hipcc")
    add(rocm .. "/lib/llvm/bin/clang")
    add(rocm .. "/lib/llvm/bin/clang++")
  end

  for _, path in ipairs(extra_drivers or {}) do
    add(path)
  end

  if #drivers > 0 then
    cmd[#cmd + 1] = "--query-driver=" .. table.concat(drivers, ",")
  end
  return cmd
end

M.lsp_settings = {
  clangd = {
    cmd = clangd_cmd(),
  },
  pyright = {
    settings = {
      python = {
        analysis = {
          autoSearchPaths = true,
          diagnosticMode = "openFilesOnly",
          useLibraryCodeForTypes = true,
        },
      },
    },
  },
  lua_ls = {
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
}

M.formatters_by_ft = {
  lua = { "stylua" },
  c = { "clang_format" },
  cpp = { "clang_format" },
  python = { "ruff_format" },
  sh = { "shfmt" },
  bash = { "shfmt" },
  json = { "prettier" },
  yaml = { "prettier" },
  markdown = { "prettier" },
}
for ft in pairs(M.formatters_by_ft) do
  local language = ft == "sh" and "bash" or ft
  if not selected[language] then M.formatters_by_ft[ft] = nil end
end

local function prepend_mason_bin()
  local bin = vim.fn.stdpath "data" .. "/mason/bin"
  local path = vim.env.PATH or ""
  if not vim.tbl_contains(vim.split(path, ":", { plain = true }), bin) then
    vim.env.PATH = bin .. ":" .. path
  end
end

local function runs(tool)
  if vim.fn.executable(tool.executable) == 0 then return false end
  local result = vim.system(tool.probe, { text = true, timeout = 10000 }):wait()
  return result.code == 0
end

local function portable_target(tool)
  if not tool.portable then return nil end
  local uname = vim.uv.os_uname()
  if uname.sysname ~= "Linux" then return nil end
  local targets = {
    x86_64 = "linux_x64",
    amd64 = "linux_x64",
    aarch64 = "linux_arm64",
    arm64 = "linux_arm64",
  }
  return targets[uname.machine]
end

-- Called by envup after lazy.nvim restores the pinned plugins. MasonInstall is
-- synchronous in headless mode, so envup does not report success while tools
-- are still downloading in the background.
function M.ensure()
  if not M.plugins_enabled() then return end
  prepend_mason_bin()

  local missing = {}
  local targeted = {}
  local needed = {}
  for _, tool in ipairs(M.mason_tools) do
    if not runs(tool) then
      needed[#needed + 1] = tool.package
      local target = portable_target(tool)
      if target then
        targeted[target] = targeted[target] or {}
        targeted[target][#targeted[target] + 1] = tool.package
      else
        missing[#missing + 1] = tool.package
      end
    end
  end

  if #missing > 0 or next(targeted) ~= nil then
    if M.offline() then
      vim.api.nvim_err_writeln(
        "[envup] nvim tools missing or unusable while offline: " .. table.concat(needed, ", ")
      )
      vim.cmd "cquit 1"
      return
    end
    local mason = require "mason.api.command"
    if #missing > 0 then mason.MasonInstall(missing, { force = true, strict = true }) end
    for target, packages in pairs(targeted) do
      mason.MasonInstall(packages, { force = true, strict = true, target = target })
    end
  end

  prepend_mason_bin()
  local unavailable = {}
  for _, tool in ipairs(M.mason_tools) do
    if not runs(tool) then
      unavailable[#unavailable + 1] = tool.executable
    end
  end
  if #unavailable > 0 then
    vim.api.nvim_err_writeln("[envup] nvim tools unavailable after install: " .. table.concat(unavailable, ", "))
    vim.cmd "cquit 1"
    return
  end

  print("[envup] nvim LSP servers and formatters ready")
end

function M.ensure_plugins(mode)
  assert(mode == "restore" or mode == "sync", "invalid Lazy install mode: " .. tostring(mode))
  assert(not M.offline(), "cannot restore plugins while offline")
  local config = require "lazy.core.config"
  assert(config.spec, "Lazy configuration did not load")
  -- Lazy 85c7ff3 Task:spawn streams headless failures without recording task errors.
  config.options.headless.process = false
  -- Sync can remove entries from to_clean; retain them to inspect failed cleanup tasks.
  local plugins = vim.list_extend(vim.tbl_values(config.plugins), config.to_clean or {})
  require("lazy")[mode]({ wait = true, show = false })
  vim.list_extend(plugins, vim.tbl_values(config.plugins))
  vim.list_extend(plugins, config.to_clean or {})
  local failed = {}
  for _, plugin in pairs(config.plugins) do
    if not plugin._.installed then failed[plugin.name .. ":not-installed"] = true end
  end
  for _, plugin in ipairs(plugins) do
    for _, task in ipairs(plugin._.tasks or {}) do
      if task:has_errors() then failed[plugin.name .. ":" .. task.name] = true end
    end
  end
  for _, notice in ipairs(config.spec.notifs or {}) do
    if notice.level >= vim.log.levels.ERROR then failed["configuration: " .. notice.msg] = true end
  end
  local errors = vim.tbl_keys(failed)
  table.sort(errors)
  assert(#errors == 0, "nvim plugin installation failed: " .. table.concat(errors, ", "))
end

function M.missing_parsers()
  local missing = {}
  for _, language in ipairs(M.treesitter_parsers) do
    local path = vim.fn.stdpath "data" .. "/lazy/nvim-treesitter/parser/" .. language .. ".so"
    local ok
    if vim.fn.filereadable(path) == 1 then
      ok = pcall(vim.treesitter.language.add, language, { path = path })
    else
      ok = pcall(vim.treesitter.language.add, language)
    end
    if not ok then missing[#missing + 1] = language end
  end
  return missing
end

function M.ensure_parsers()
  if not M.plugins_enabled() then return end
  local missing = M.missing_parsers()
  if #missing == 0 then return end
  assert(not M.offline(), "nvim parsers unavailable while offline: " .. table.concat(missing, ", "))
  local install = require "nvim-treesitter.install"
  -- Git inherits envup's mirror routing; the tarball downloader bypasses it.
  install.prefer_git = true
  install.commands.TSInstallSync["run!"](missing)
  -- The pinned installer can print a compile/download error and still return normally.
  missing = M.missing_parsers()
  assert(#missing == 0, "nvim parsers unavailable after install: " .. table.concat(missing, ", "))
end

function M.missing_plugins()
  local data = vim.fn.stdpath "data"
  local lock_path = vim.env.ENVUP_HOME and (vim.env.ENVUP_HOME .. "/modules/nvim/files/lazy-lock.json")
    or (vim.fn.stdpath "config" .. "/lazy-lock.json")
  local lock = vim.json.decode(table.concat(vim.fn.readfile(lock_path), "\n"))
  local missing = {}
  for name in pairs(lock) do
    if vim.fn.isdirectory(data .. "/lazy/" .. name) == 0 then
      missing[#missing + 1] = "plugin:" .. name
    end
  end
  if vim.fn.filereadable(data .. "/lazy/lazy.nvim/lua/lazy/init.lua") == 0 then
    missing[#missing + 1] = "lazy.nvim bootstrap"
  end
  for _, name in ipairs { "defaults", "statusline" } do
    if vim.fn.filereadable(data .. "/base46/" .. name) == 0 then
      missing[#missing + 1] = "base46:" .. name
    end
  end
  table.sort(missing)
  return missing
end

function M.check()
  if not M.plugins_enabled() then return end
  prepend_mason_bin()
  local missing = M.missing_plugins()
  for _, language in ipairs(M.missing_parsers()) do missing[#missing + 1] = "parser:" .. language end
  for _, tool in ipairs(M.mason_tools) do
    if not runs(tool) then missing[#missing + 1] = tool.executable end
  end
  table.sort(missing)
  if #missing > 0 then
    print("nvim components missing or unusable: " .. table.concat(missing, ", "))
    vim.cmd "cquit 70"
  end
end

M.prepend_mason_bin = prepend_mason_bin
M.clangd_cmd = clangd_cmd

return M
