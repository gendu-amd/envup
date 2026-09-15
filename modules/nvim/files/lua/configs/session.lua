-- Session.vim, so that a pane restored by tmux-resurrect comes back with the
-- files you had open in it.
--
-- ~/.tmux.conf sets @resurrect-strategy-nvim 'session'. That strategy replaces
-- the saved command with `nvim -S` when — and only when — the pane's directory
-- contains a Session.vim. Nothing in this config ever wrote one, so the setting
-- had been doing precisely nothing since the day it was added: every restored
-- editor pane came back as an empty nvim.
--
-- Two decisions worth knowing about:
--
-- * The session is written on a timer, not on exit. The case this exists for is
--   a machine that went down without warning, and a kernel that is going down
--   does not run VimLeavePre. An exit hook would save the sessions you did not
--   need and lose the ones you did.
--
-- * A clean quit deletes it. That keeps Session.vim out of your project
--   directories in the normal case — the file only survives when nvim was
--   killed, which is exactly when the next restore should use it. (`git` still
--   ignores it globally; a crash can leave one behind in a repo.)
--
-- Only ever active inside tmux: outside it there is nothing to restore from, so
-- there is no reason to leave a file in someone's working directory. Turn it off
-- entirely from hosts/<machine>.lua or local.lua with:
--
--     vim.g.envup_session = false

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

-- nil means "not somewhere we should be writing". $HOME and / are excluded
-- because a Session.vim there follows you into every shell you open.
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

-- An nvim showing nothing but the empty start buffer has nothing to restore,
-- and writing a file to say so is pure litter.
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
    -- Closed the last file? Take the stale session with it, so a restore does
    -- not reopen what you deliberately shut.
    discard(path)
    return
  end
  -- pcall: mksession is refused outright in a few states (the command-line
  -- window, for one), and a periodic timer must never be the thing that puts an
  -- error on your screen.
  pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(path))
end

function M.setup()
  -- Armed from VimEnter rather than here so that hosts/<machine>.lua and
  -- local.lua — which load after this file — still get a say in vim.g.envup_session.
  vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
      if not enabled() then
        return
      end

      -- Trimmed from the default: no 'blank' (empty windows restore as empty
      -- windows), no 'terminal' (resurrect already rebuilds the pane its shell
      -- was in), no 'options' (a session that pins your settings is a session
      -- that quietly reverts a config change).
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

      -- Cheap insurance either side of the timer window: the moment you step
      -- away is a good moment to have saved, and a clean quit cleans up.
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
