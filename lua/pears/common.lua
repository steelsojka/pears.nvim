local api = vim.api

local M = {}

M.activated_buf_var = "PearsActive"

M.Ns = {
  Highlight = api.nvim_create_namespace "pears.highlights",
  Range = api.nvim_create_namespace "pears.range"
}

M.Hl = {
  Pairs = "PearsHighlight"
}

return M
