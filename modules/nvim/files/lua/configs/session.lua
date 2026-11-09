-- Periodically write Session.vim inside tmux for crash/reboot restoration.
-- Clean exits remove it. Disable with vim.g.envup_session = false.

local M = {}

local SESSION_FILE = "Session.vim"
local INTERVAL_MS = 60 * 1000
local MARKER = '" envup tmux session: '
local owned = {}

local function enabled()
  if vim.g.envup_session == false then
    return false
  end
  local tmux = vim.env.TMUX
  return tmux ~= nil and tmux ~= ""
end

-- Never write a session at / or HOME.
local function session_path()
  local dir = vim.fn.getcwd()
  if dir == "" or dir == "/" or dir == vim.env.HOME then
    return nil
  end
  if vim.fn.filewritable(dir) ~= 2 then
    return nil
  end
  return dir .. "/" .. SESSION_FILE
end

local function has_real_buffer()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(buf)
      and vim.bo[buf].buftype == ""
      and vim.api.nvim_buf_get_name(buf) ~= ""
    then
      return true
    end
  end
  return false
end

local function snapshot(path)
  local stat = vim.uv.fs_lstat(path)
  if not stat or stat.type ~= "file" then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return { dev = stat.dev, ino = stat.ino, lines = lines }
end

local function discard(path)
  if path then
    if owned[path] and vim.deep_equal(snapshot(path), owned[path]) then
      pcall(vim.uv.fs_unlink, path)
    end
    owned[path] = nil
  else
    for saved in pairs(owned) do
      discard(saved)
    end
  end
end

function M.save()
  if not enabled() then
    return
  end
  local path = session_path()
  if not path then
    return
  end
  if not has_real_buffer() then
    discard(path)
    return
  end
  local previous = snapshot(path)
  if vim.uv.fs_lstat(path) then
    -- Leave user sessions, links, and edits made after our last save untouched.
    local digest = previous and (previous.lines[1] or ""):match('^" envup tmux session: %d+ (%x+)$')
    if not digest or digest ~= vim.fn.sha256(table.concat(previous.lines, "\n", 2)) then
      return
    end
    if owned[path] and not vim.deep_equal(previous, owned[path]) then
      return
    end
  end
  -- A timer must not surface errors from temporary unsupported editor states.
  local ok = pcall(vim.cmd, (previous and "mksession! " or "mksession ") .. vim.fn.fnameescape(path))
  if not ok then
    return
  end
  local saved = snapshot(path)
  if not saved then
    return
  end
  local digest = vim.fn.sha256(table.concat(saved.lines, "\n"))
  table.insert(saved.lines, 1, MARKER .. vim.uv.os_getpid() .. " " .. digest)
  local wrote, result = pcall(vim.fn.writefile, saved.lines, path)
  if wrote and result == 0 then
    owned[path] = snapshot(path)
  end
end

function M.setup()
  -- Delay until host/local overrides have loaded.
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      if not enabled() then
        return
      end

      -- Do not restore empty windows, terminals, or stale editor options.
      vim.opt.sessionoptions = { "buffers", "curdir", "folds", "help", "tabpages", "winsize" }

      local timer = vim.uv.new_timer()
      if timer then
        timer:start(
          INTERVAL_MS,
          INTERVAL_MS,
          vim.schedule_wrap(function()
            M.save()
          end)
        )
      end

      vim.api.nvim_create_autocmd("FocusLost", { callback = M.save })
      vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
          discard()
        end,
      })
    end,
  })
end

return M
