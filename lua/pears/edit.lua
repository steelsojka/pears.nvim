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

M.left = M.make_feedkey("<Left>")
M.right = M.make_feedkey("<Right>")
M.delete = M.make_feedkey("<Del>")
M.backspace = M.make_feedkey("<BS>")

M.Queue = {}

function M.Queue.new()
  local self = {
    _queue = {}
  }

  return setmetatable(self, {__index = M.Queue})
end

function M.Queue:add(fn, args)
  table.insert(self._queue, { fn, args })
end

function M.Queue:execute()
  for _, item in ipairs(self._queue) do
    item[1](unpack(item[2] or {}))
  end
end

return M
