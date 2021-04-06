local api = vim.api

local M = {}

local buf_table_mt = {
}

function M.is_in_range(row, col, range)
  local start_row, start_col, end_row, end_col  = unpack(range)

  return (row > start_row or (start_row == row and col >= start_col))
    and (row < end_row or (row == end_row and col <= end_col))
end

function M.get_surrounding_chars(bufnr, count)
  count = count or 1

  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]

  if line then
    local before = string.sub(line, col, col + count - 1)
    local after = string.sub(line, col + count, col + count)

    return before, after
  end
end

function M.make_buf_table(cleanup)
  return setmetatable({}, {
    __newindex = function(tbl, bufnr, value)
      local existing = rawget(tbl, bufnr)

      rawset(tbl, bufnr, value)

      if not existing then
        api.nvim_buf_attach(bufnr, false, {
          on_detach = function()
            local v = rawget(tbl, bufnr)

            rawset(tbl, bufnr, nil)

            if cleanup then
              cleanup(v)
            end

            return true
          end
        })
      end
    end
  })
end

function M.pull(list, item, comparer)
  local index

  for i, list_item in ipairs(list) do
    if comparer(list_item, item) then
      index = i
      break
    end
  end

  if not index then return end

  local removed = list[index]

  table.remove(list, index)

  return removed
end

function M.constant(value)
  return function() return value end
end

M.noop = M.constant(nil)

return M
