-- Disable expensive editor features above the configured byte threshold.
-- Set vim.g.envup_bigfile_bytes = 0 to disable this guard.

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
      vim.bo[args.buf].undofile = false
      vim.bo[args.buf].swapfile = false
      vim.bo[args.buf].syntax = "off"

      vim.schedule(function()
        vim.notify(
          ("[envup] %.0f MB — syntax, LSP and undo are off for this buffer"):format(stat.size / 1024 / 1024),
          vim.log.levels.WARN
        )
      end)
    end,
  })

  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      if not vim.b[args.buf].envup_bigfile then
        return
      end
      pcall(vim.treesitter.stop, args.buf)
      vim.wo.foldenable = false
    end,
  })

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
