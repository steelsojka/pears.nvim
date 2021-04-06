local Common = require "pears.common"
local Utils = require "pears.utils"
local api = vim.api

local Context = {}

function Context.combine_range(start, end_)
  local start_row, start_col = unpack(start)
  local end_row, end_col = unpack(end_)

  return {start_row, start_col, end_row, end_col}
end

function Context.new(bufnr, key, start_range, end_range)
  local self = {
    id = math.random(100000),
    bufnr = bufnr,
    key = key,
    _start_range = start_range,
    _end_range = end_range
    -- start_outer_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, start_range[1], start_range[2], {}),
    -- start_inner_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, start_range[3], start_range[4], {}),
    -- end_outer_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, end_range[1], end_range[2], {}),
    -- end_inner_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, end_range[3], end_range[4], {})
  }

  return setmetatable(self, {__index = Context})
end

function Context:start()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.start_outer_mark, {})
end

function Context:end_()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.end_outer_mark, {})
end

function Context:start_inner()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.start_inner_mark, {})
end

function Context:end_inner()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.namespace, self.end_inner_mark, {})
end

function Context:start_range()
  return Context.combine_range(self:start(), self:start_inner())
end

function Context:end_range()
  return Context.combine_range(self:end_inner(), self:end_())
end

function Context:range()
  return Context.combine_range(self:start(), self:end_())
end

function Context:inner_range()
  return Context.combine_range(self:start_inner(), self:end_inner())
end

function Context:is_in_range(row, col)
  return Utils.is_in_range(row, col, self:range())
end

function Context:mark()
  self.start_outer_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._start_range[1], self._start_range[2], {})
  self.start_inner_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._start_range[3], self._start_range[4], {})
  self.end_outer_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._end_range[1], self._end_range[2], {})
  self.end_inner_mark = api.nvim_buf_set_extmark(self.bufnr, Common.namespace, self._end_range[3], self._end_range[4], {})
end

function Context:destroy()
  if self.start_inner_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.start_inner_mark)
  end
  if self.end_inner_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.end_inner_mark)
  end
  if self.start_outer_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.start_outer_mark)
  end
  if self.end_outer_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.end_outer_mark)
  end
end

function Context:is_empty()
  local range = self:inner_range()

  return range[1] == range[3] and range[4] - range[2] == 1
end

function Context:equals(context)
  return context.id == self.id
end

return Context
