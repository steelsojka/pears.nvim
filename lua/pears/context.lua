local Common = require "pears.common"
local Utils = require "pears.utils"
local api = vim.api

local Context = {}

function Context.combine_range(start, end_)
  local start_row, start_col = unpack(start)
  local end_row, end_col = unpack(end_)

  return {start_row, start_col, end_row, end_col}
end

function Context.new(bufnr, key, range)
  local self = {
    id = math.random(100000),
    bufnr = bufnr,
    key = key,
    _range = range
  }

  return setmetatable(self, {__index = Context})
end

function Context:start()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.start_mark, {})
end

function Context:end_()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.end_mark, {})
end

function Context:range()
  return Context.combine_range(self:start(), self:end_())
end

function Context:is_in_range(row, col)
  return Utils.is_in_range(row, col, self:range())
end

function Context:mark()
  self.start_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._range[1], self._range[2], {
    right_gravity = false
  })
  self.end_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._range[3], self._range[4], {})
end

function Context:destroy()
  if self.end_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.end_mark)
  end
  if self.start_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.start_mark)
  end
end

function Context:is_empty()
  local range = self:range()

  return range[1] == range[3] and range[4] - range[2] == 1
end

function Context:equals(context)
  return context.id == self.id
end

return Context
