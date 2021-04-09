local api = vim.api

local M = {}

function M.get_cursor()
  local row, col = unpack(api.nvim_win_get_cursor(0))

  return {row - 1, col}
end

function M.is_in_range(row, col, range)
  local start_row, start_col, end_row, end_col  = unpack(range)

  return (row > start_row or (start_row == row and col >= start_col))
    and (row < end_row or (row == end_row and col <= end_col))
end

function M.get_surrounding_chars(bufnr, position, lead_count, tail_count)
  lead_count = lead_count or 1
  tail_count = tail_count or lead_count

  local row, col = unpack(position or M.get_cursor())
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]

  if line then
    local before = string.sub(line, math.max(col - lead_count + 1, 0), col)
    local after = string.sub(line, col + 1, col + tail_count)

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

function M.has_leading_alpha(bufnr)
  local before = M.get_surrounding_chars(bufnr, nil, 1)

  return string.match(before, "[a-zA-Z]")
end

function M.partial(fn, ...)
  local args = {select(1, ...)}

  return function(...)
    return fn(unpack(args), ...)
  end
end

function M.is_type(_type, v)
  return type(v) == _type
end

M.is_table = M.partial(M.is_type, "table")
M.is_number = M.partial(M.is_type, "number")
M.is_func = M.partial(M.is_type, "function")

function M.negate(fn)
  return function(...) return not fn(...) end
end

function M.unary(fn)
  return function() fn() end
end

function M.constant(value)
  return function() return value end
end

function M.key_by(tbl, prop)
  local result = {}

  for _, v in ipairs(tbl) do
    result[v[prop]] = v
  end

  return result
end

M.noop = M.constant(nil)

return M
