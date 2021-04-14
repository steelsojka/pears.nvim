local api = vim.api

local M = {}

M.log = (function()
  local count = 1

  return function(...)
    print(count..": ", unpack(M.map(function(v)
      return vim.inspect(v)
    end, {select(1, ...)})))
    count = count + 1

    return select(1, ...)
  end
end)()

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
    local after = string.sub(line, col + 1, math.min(col + tail_count, #line + 1))

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

function M.combine_range(start, end_)
  local start_row, start_col = unpack(start)
  local end_row, end_col = unpack(end_)

  return {start_row, start_col, end_row, end_col}
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
M.is_string = M.partial(M.is_type, "string")

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
M.identity = function(a) return a end

function M.map(predicate, list)
  local result = {}

  for i, item in ipairs(list) do
    table.insert(result, predicate(item, i))
  end

  return result
end

M.KeyMap = {}

function M.KeyMap.new()
  return setmetatable({
    items = {}
  }, {__index = M.KeyMap})
end

function M.KeyMap:set(key, item)
  if not self.items[key] then
    self.items[key] = {}
  end

  table.insert(self.items[key], item)
end

function M.KeyMap:get(key)
  return self.items[key]
end

function M.KeyMap:iter()
  local current_list
  local current_item
  local list_index = next(self.items)
  local item_index

  function iter()
    local list = self.items[list_index]

    if list then
      item_index = next(list, item_index)

      if item_index and list[item_index] then
        return list[item_index]
      else
        list_index = next(self.items, list_index)

        return iter()
      end
    end

    return nil
  end

  return iter
end

function M.KeyMap:reset()
  self.items = {}
end

function M.KeyMap:delete(key, item)
  if item then
    if self.items[key] then
      M.pull(self.items[key], item, function(a, b) return a == b end)
    end
  else
    self.items[key] = nil
  end
end

return M
