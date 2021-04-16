local ts = require "vim.treesitter"
local Utils = require "pears.utils"
local api = vim.api

local M = {}

-- Gets the current lang at a position.
-- Will use treesitter to get the most specific language if possible.
function M.get_current_lang(bufnr, ft, position)
  ft = ft or api.nvim_buf_get_option(bufnr, "filetype")

  local has_parser, ts_parser = pcall(ts.get_parser, bufnr, ft)

  if has_parser and ts_parser then
    local row, col = unpack(position or Utils.get_cursor())
    local tree_at_pos = ts_parser:language_for_range({row, col, row, col})

    if tree_at_pos then
      return tree_at_pos:lang()
    end
  end

  return ft
end

return M
