-- Use OSC 52 copy only when no usable native clipboard exists. Paste reads
-- Nvim's register because many terminals intentionally refuse OSC 52 reads.

-- xclip/xsel require a display; executable presence alone is insufficient.
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

-- Terminals silently drop oversized OSC 52 payloads.
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
