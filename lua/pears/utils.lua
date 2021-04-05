local api = vim.api

local M = {}

function M.is_in_range(row, col, range)
  local start_row, start_col, end_row, end_col  = unpack(range)

  return (row > start_row or (start_row == row and col >= start_col))
    and (row < end_row or (row == end_row and col <= end_col))
end

function M.get_wrapped_chars(bufnr)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1]

  if line then
    local before = string.sub(line, col, col)
    local after = string.sub(line, col + 1, col + 1)

    return before, after
  end
end

return M
