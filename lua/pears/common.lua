local api = vim.api

local M = {}

M.namespace = api.nvim_create_namespace("pears")
M.activated_buf_var = "PearsActive"

return M
