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

M.Queue = {}

function M.Queue.new(in_loop)
  local self = {
    _queue = {},
    _in_loop = in_loop
  }

  return setmetatable(self, {__index = M.Queue})
end

function M.Queue:add(fn, args)
  table.insert(self._queue, { fn, args })
end

function M.Queue:execute()
  if self:is_empty() then return end

  if self._in_loop then
    vim.schedule(function() self:_execute() end)
  else
    self:_execute()
  end
end

function M.Queue:is_empty()
  return #self._queue == 0
end

function M.Queue:_execute()
  for _, item in ipairs(self._queue) do
    item[1](unpack(item[2] or {}))
  end
end

return M
