-- Periodically write Session.vim inside tmux for crash/reboot restoration.
-- Clean exits remove it. Disable with vim.g.envup_session = false.

local M = {}

local SESSION_FILE = "Session.vim"
local INTERVAL_MS = 60 * 1000

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

local function discard(path)
  path = path or session_path()
  if path and vim.uv.fs_stat(path) then
    pcall(vim.uv.fs_unlink, path)
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
  -- A timer must not surface errors from temporary unsupported editor states.
  pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(path))
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
