-- Clipboard over SSH, via OSC 52.
--
-- On a server there is no clipboard: no X display, no pbcopy, and NvChad sets
-- clipboard=unnamedplus, so every yank went to a provider that did not exist.
-- OSC 52 is a terminal escape sequence — the text travels back over the SSH
-- connection that is already open and lands on the clipboard of the machine you
-- are actually sitting at. No X11 forwarding, no root, no daemon, no extra port.
--
-- Two things this file is careful about:
--
--  1. It only takes over when nvim has no real clipboard tool it could use.
--     A desktop with xclip/wl-copy/pbcopy keeps the native provider, which is
--     strictly better because it can paste as well as copy.
--
--  2. Paste is deliberately NOT the OSC 52 reader. Reading the clipboard means
--     asking the terminal and waiting for an answer, and the terminals we use
--     implement OSC 52 write-only on purpose (letting a remote program read your
--     clipboard is a real security hole). Windows Terminal and VS Code / Cursor
--     both refuse to answer, so nvim would block for its full timeout — a ~10s
--     freeze on every `p`. Pasting from nvim's own register is what you want
--     anyway; to paste something from the *outside* world, use the terminal's
--     own paste (Ctrl+Shift+V), which arrives as ordinary keystrokes.
--
-- Inside tmux this needs `set -s set-clipboard on`, which modules/tmux sets.
-- Terminal-side requirements are in docs/CLIPBOARD.md.

-- Is there a clipboard tool that would actually work here? Presence on PATH is
-- not enough: xclip on a headless box with no DISPLAY is an error message.
local function has_native_clipboard()
  local exe = function(c) return vim.fn.executable(c) == 1 end
  if exe "pbcopy" then return true end                       -- macOS
  if exe "clip.exe" then return true end                     -- WSL
  if (vim.env.WAYLAND_DISPLAY or "") ~= "" and exe "wl-copy" then return true end
  if (vim.env.DISPLAY or "") ~= "" and (exe "xclip" or exe "xsel") then return true end
  return false
end

if has_native_clipboard() then return end

local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
if not ok then return end                                    -- nvim < 0.10

-- Terminals cap how much they will accept in one escape sequence, and they drop
-- an oversized one without saying so. Better to be told than to discover the
-- clipboard still holds what was in it ten minutes ago.
local LIMIT = 64 * 1024

local function copy(reg)
  local inner = osc52.copy(reg)
  return function(lines, regtype)
    local n = 0
    for _, l in ipairs(lines) do n = n + #l + 1 end
    if n > LIMIT then
      vim.notify(
        ("clipboard: %d KB is too large for OSC 52 — copied to register %s only")
          :format(math.floor(n / 1024), reg),
        vim.log.levels.WARN
      )
      return
    end
    inner(lines, regtype)
  end
end

local function paste()
  return vim.split(vim.fn.getreg('"') or "", "\n")
end

vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = copy "+", ["*"] = copy "*" },
  paste = { ["+"] = paste, ["*"] = paste },
}
