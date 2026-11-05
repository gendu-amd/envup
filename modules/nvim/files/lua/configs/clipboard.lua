-- Copy-only providers paste from Nvim's register: terminals often refuse
-- OSC 52 reads, and clip.exe has no read operation.

local function paste()
  -- Nvim 0.10 accepts one type character and infers block width from the lines
  -- (neovim v0.10.4, src/nvim/ops.c:get_clipboard).
  return { vim.fn.getreg('"', 1, true), vim.fn.getregtype('"'):sub(1, 1) }
end

-- xclip/xsel require a display; executable presence alone is insufficient.
local function has_native_clipboard()
  local exe = function(c) return vim.fn.executable(c) == 1 end
  if exe "win32yank.exe" then return true end
  if vim.fn.has "mac" == 1 and exe "pbcopy" and exe "pbpaste" then return true end
  if (vim.env.WAYLAND_DISPLAY or "") ~= "" and exe "wl-copy" and exe "wl-paste" then return true end
  if (vim.env.DISPLAY or "") ~= "" and (exe "xclip" or exe "xsel") then return true end
  return false
end

if has_native_clipboard() then return end

-- Nvim 0.10's provider/clipboard.vim does not autodetect clip.exe on WSL.
if vim.fn.executable "clip.exe" == 1 then
  vim.g.clipboard = {
    name = "WSL clip.exe (copy only)",
    copy = { ["+"] = { "clip.exe" }, ["*"] = { "clip.exe" } },
    paste = { ["+"] = paste, ["*"] = paste },
    cache_enabled = 0,
  }
  return
end

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

vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = copy "+", ["*"] = copy "*" },
  paste = { ["+"] = paste, ["*"] = paste },
}
