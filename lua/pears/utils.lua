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

function M.split_line_at(bufnr, position)
  position = position or M.get_cursor()

  local row, col = unpack(position)
  local line = api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]

  if line then
    local before = string.sub(line, 1, math.max(0, col))
    local after = string.sub(line, col + 1)

    return before, after, position
  end
end

function M.get_surrounding_chars(bufnr, position, lead_count, tail_count)
  lead_count = lead_count or 1
  tail_count = tail_count or lead_count

  local before, after, split_pos = M.split_line_at(bufnr, position)

  if before and after then
    return
      string.sub(before, #before - lead_count + 1),
      string.sub(after, 1, tail_count)
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

  comparer = comparer or function(a, b) return a == b end

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

function M.has_leading_alpha(bufnr, position)
  local before = M.get_surrounding_chars(bufnr, position, 1)

  return string.match(before, "[a-zA-Z]")
end

function M.combine_range(start, end_)
  local start_row, start_col = unpack(start)
  local end_row, end_col = unpack(end_)

  return {start_row, start_col, end_row, end_col}
end

function M.get_inner_range(range_a, range_b)
  return {range_a[3], range_a[4], range_b[1], range_b[2]}
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

function M.find(predicate, list)
  local index
  local item

  for i = 1, #list, 1 do
    if predicate(list[i], i) then
      index = i
      item = list[i]
      break
    end
  end

  return item, index
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

function M.get_content_from_range(bufnr, range)
  local start_row, start_col, end_row, end_col = unpack(range)
  local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  local first_line = string.sub(lines[1] or "", start_col + 1)

  if start_row == end_row then
    return {string.sub(first_line, 1, end_col - start_col)}
  end

  local last_line = string.sub(lines[#lines] or "", 1, end_col)

  lines[1] = first_line
  lines[#lines] = last_line

  return lines
end

function M.get_position_offset(start_position, position)
  return {
    math.max(position[1] - start_position[1], 0),
    math.max(position[2] - start_position[2], 0)}
end

function M.get_wrapping_ranges(bufnr, row, col, range)
  local buf_range = range or M.get_buf_range(bufnr)

  return {buf_range[1], buf_range[2], row, col}, {row, col, buf_range[3], buf_range[4]}
end

function M.is_range_empty(range)
  return range[1] == range[3] and range[2] == range[4] - 1
end

function M.get_buf_range(bufnr)
  local lines = api.nvim_buf_get_lines(bufnr, 0, -1, true)
  local last_line = lines[#lines]

  return {0, 0, #lines, #last_line}
end

-- Reverse a string while keeping escape sequences in place.
function M.reverse_str(str)
  local i = 1
  local result = ""

  while i <= #str do
    local char = string.sub(str, i, i)
    local peek_char = string.sub(str, i + 1, i + 1)

    if char == "\\" and peek_char then
      i = i + 1
      result = "\\" .. peek_char .. result
    else
      result = char .. result
    end

    i = i + 1
  end

  return result
end

-- Strip escape sequences from a string.
function M.strip_escapes(str)
  local i = 1
  local result = ""

  while i <= #str do
    local char = string.sub(str, i, i)
    local peek_char = string.sub(str, i + 1, i + 1)

    if char == "\\" and peek_char then
      result = result .. peek_char
      i = i + 1
    else
      result = result .. char
    end

    i = i + 1
  end

  return result
end

function M.match(str, pattern_or_list)
  if M.is_table(pattern_or_list) then
    for _, pattern in ipairs(pattern_or_list) do
      if not string.match(str, pattern) then
        return false
      end
    end
  elseif M.is_string(pattern_or_list) then
    return string.match(str, pattern_or_list)
  end

  return true
end

function M.shift_pos_back(pos, amount)
  local row, col = unpack(pos)

  return {row, math.max(0, col - amount)}
end

function M.clone_tbl(tbl)
  return vim.tbl_extend("force", {}, tbl)
end

function M.escape_pattern(pattern)
  return string.gsub(pattern, "[%^%$%(%)%%.%[%]%*%+%-%?]", "%%%0")
end

function M.make_range(start, end_)
  return {start[1], start[2], end_[1], end_[2]}
end

function M.set_timeout(fn, timeout)
  local timer = vim.loop.new_timer()

  timer:start(timeout, 0, function()
    fn()

    timer:stop()
    timer:close()
  end)

  return timer
end

function M.to_iter(list_or_func)
  if M.is_func(list_or_func) then
    return list_or_func
  elseif M.is_table(list_or_func) then
    return ipairs(list_or_func)
  end

  return M.noop
end

return M
