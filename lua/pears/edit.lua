local Utils = require "pears.utils"
local api = vim.api

local M = {}

function M.insert(text)
  api.nvim_put({text}, "c", false, true)
end

function M.make_feedkey(key)
  return function(times)
    times = times or 1

    while times > 0 do
      api.nvim_feedkeys(api.nvim_replace_termcodes(key, true, false, true), "n", true)
      times = times - 1
    end
  end
end

function M.prevent_input()
  vim.cmd [[let v:char = ""]]
end

M.left = M.make_feedkey("<Left>")
M.right = M.make_feedkey("<Right>")
M.delete = M.make_feedkey("<Del>")
M.backspace = M.make_feedkey("<BS>")
M.enter = M.make_feedkey("<CR>")
M.return_and_indent = Utils.unary(M.make_feedkey("<CR><C-c>O"))

return M
