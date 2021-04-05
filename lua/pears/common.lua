local api = vim.api

local M = {}

M.namespace = api.nvim_create_namespace("pears")
M.context_var = "pears"

return M
