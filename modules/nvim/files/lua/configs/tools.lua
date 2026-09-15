local M = {}

-- One inventory drives installation, LSP setup and formatting. Keep Mason's
-- package name beside the executable it must leave behind: an install only
-- counts when the command Neovim will call is actually runnable.
M.mason_tools = {
  { package = "clangd", executable = "clangd", probe = { "clangd", "--version" } },
  { package = "pyright", executable = "pyright-langserver", probe = { "pyright", "--version" } },
  {
    package = "lua-language-server",
    executable = "lua-language-server",
    probe = { "lua-language-server", "--version" },
  },
  {
    package = "bash-language-server",
    executable = "bash-language-server",
    probe = { "bash-language-server", "--version" },
  },
  { package = "clang-format", executable = "clang-format", probe = { "clang-format", "--version" } },
  { package = "stylua", executable = "stylua", probe = { "stylua", "--version" }, portable = true },
  { package = "ruff", executable = "ruff", probe = { "ruff", "--version" } },
  { package = "shfmt", executable = "shfmt", probe = { "shfmt", "--version" } },
  { package = "prettier", executable = "prettier", probe = { "prettier", "--version" } },
}

M.lsp_servers = { "clangd", "pyright", "lua_ls", "bashls" }

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
    if vim.env.ENVUP_NET == "offline" or vim.env.ENVUP_OFFLINE == "1" then
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

M.prepend_mason_bin = prepend_mason_bin
M.clangd_cmd = clangd_cmd

return M
