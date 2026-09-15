-- Opening a big file should be boring.
--
-- The way it goes wrong is always the same: you tail a 200 MB log on a server,
-- nvim opens it, treesitter starts parsing, an LSP starts indexing, and the
-- editor stops answering. Over SSH you cannot even tell whether it is hung or
-- the connection died, so you kill the terminal — and take the rest of the
-- session with it.
--
-- Past the threshold this strips the buffer back to what a pager does: no
-- syntax, no treesitter, no LSP, no undo history, no swap file. Everything else
-- about the buffer still works.
--
--   vim.g.envup_bigfile_bytes = 5 * 1024 * 1024   -- raise it in hosts/<machine>.lua
--   vim.g.envup_bigfile_bytes = 0                 -- off

local M = {}

local DEFAULT_BYTES = 1536 * 1024 -- 1.5 MB

local function limit()
  local n = vim.g.envup_bigfile_bytes
  if n == nil then
    return DEFAULT_BYTES
  end
  return n
end

function M.setup()
  local group = vim.api.nvim_create_augroup("EnvupBigFile", { clear = true })

  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(args)
      local max = limit()
      if max <= 0 then
        return
      end
      local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(args.buf))
      if not stat or stat.size <= max then
        return
      end

      vim.b[args.buf].envup_bigfile = true
      -- Undo of a 200 MB buffer is the memory problem, not the safety net.
      vim.bo[args.buf].undofile = false
      vim.bo[args.buf].swapfile = false
      -- 'syntax' is what the regex highlighter reads; setting it before the
      -- read is what keeps it from ever starting.
      vim.bo[args.buf].syntax = "off"

      vim.schedule(function()
        vim.notify(
          ("[envup] %.0f MB — syntax, LSP and undo are off for this buffer"):format(stat.size / 1024 / 1024),
          vim.log.levels.WARN
        )
      end)
    end,
  })

  -- treesitter attaches on BufReadPost, after the decision above is recorded.
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      if not vim.b[args.buf].envup_bigfile then
        return
      end
      pcall(vim.treesitter.stop, args.buf)
      -- Folding walks the whole buffer to decide where the folds are.
      vim.wo.foldenable = false
    end,
  })

  -- Cheaper to let a server attach and send it away than to reimplement
  -- lspconfig's filetype matching here in order to pre-empt it.
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      if not vim.b[args.buf].envup_bigfile then
        return
      end
      vim.schedule(function()
        pcall(vim.lsp.buf_detach_client, args.buf, args.data.client_id)
      end)
    end,
  })
end

return M
