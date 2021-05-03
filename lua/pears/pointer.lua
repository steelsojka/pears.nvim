local PearTree = require "pears.pear_tree"

local M = {}

M.Direction = {
  Forward = 1,
  Backwards = 2
}

function M.move(row, col, lines, direction)
  local increment = M.Direction.Backwards == direction and -1 or 1
  local current_line = lines[row + 1]
  local captured = ""

  if not current_line then return end

  col = col + increment

  if col < 0 then
    row = row - 1
    current_line = lines[row + 1]
    col = current_line and #current_line or 0
  elseif col > #current_line then
    row = row + 1
    current_line = lines[row + 1]
    col = 0
  else
    captured = string.sub(current_line, col + 1, col + 1)
  end

  return captured, row, col
end

function M.match(trie, row, col, lines, direction)
  local current = trie
  local last = nil
  local last_row = row
  local last_col = col
  local char = M.get_char_at(row, col, lines)

  while char and current do
    if #char > 0 then
      local key = PearTree.make_key(char)

      current = current.branches[key]

      if current then
        if current.leaf then
          last = current
          last_row = row
          last_col = col
        elseif current.wildcard then
          last = current
        end
      else
        break
      end
    else
      -- new line
      current = nil
    end

    char, row, col = M.move(row, col, lines, direction)
  end

  if last then
    return last, last_row, last_col
  end
end

function M.get_char_at(row, col, lines)
  local line = lines[row + 1]

  if line then
    return string.sub(line, col + 1, col + 1)
  end
end

function M.at_start(row, col)
  return row <= 0 and col < 0
end

function M.at_end(row, col, lines)
  local last_line = lines[#lines]

  return row >= #lines and col > #last_line
end

function M.lt(row_a, col_a, row_b, col_b)
  return row_a < row_b
    or (row_a == row_b and col_a < col_b)
end

function M.gt(row_a, col_a, row_b, col_b)
  return not M.lt(row_a, col_a, row_b, col_b)
end

function M.eq(row_a, col_a, row_b, col_b)
  return row_a == row_b and col_a == col_b
end

function M.min(row_a, col_a, row_b, col_b)
  if M.lt(row_a, col_a, row_b, col_b) then
    return row_a, col_a
  end

  return row_b, col_b
end

function M.max(row_a, col_a, row_b, col_b)
  local min_row, min_col = M.min(row_a, col_a, row_b, col_b)

  if min_row == row_a and min_col == col_a then
    return row_b, col_b
  end

  return row_a, col_a
end

return M
