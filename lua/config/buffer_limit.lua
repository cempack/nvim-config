-- Keep at most `max` file buffers open, so bufferline never shows more than
-- that many tabs. Opening another closes the least recently used buffer that is
-- safe to close: not modified, not shown in any window, and not pinned in
-- bufferline. When none is safe to close, the limit is exceeded rather than
-- losing work. A closed buffer can be reopened with <C-o> or from the pickers.
local M = {}

M.max = 6

local function is_pinned(buf)
  local ok, groups = pcall(require, "bufferline.groups")
  if not ok then
    return false
  end
  local ok_pinned, pinned = pcall(groups._is_pinned, { id = buf })
  return ok_pinned and pinned == true
end

local function trim()
  local buffers = vim.tbl_filter(function(info)
    return vim.bo[info.bufnr].buftype == ""
  end, vim.fn.getbufinfo({ buflisted = 1 }))

  local excess = #buffers - M.max
  if excess <= 0 then
    return
  end

  -- lastused has a one-second resolution; the older buffer number breaks ties.
  table.sort(buffers, function(a, b)
    if a.lastused ~= b.lastused then
      return a.lastused < b.lastused
    end
    return a.bufnr < b.bufnr
  end)

  for _, info in ipairs(buffers) do
    if excess == 0 then
      break
    end
    if info.changed == 0 and #info.windows == 0 and not is_pinned(info.bufnr) then
      if pcall(vim.cmd.bdelete, info.bufnr) then
        excess = excess - 1
      end
    end
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("buffer_limit", { clear = true }),
    callback = function()
      vim.schedule(trim)
    end,
  })
end

return M
