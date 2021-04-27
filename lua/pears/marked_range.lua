local Common = require "pears.common"
local Utils = require "pears.utils"
local api = vim.api

local MarkedRange = {}

function MarkedRange.combine_range(start, end_)
  local start_row, start_col = unpack(start)
  local end_row, end_col = unpack(end_)

  return {start_row, start_col, end_row, end_col}
end

function MarkedRange.new(bufnr, range)
  local self = {
    bufnr = bufnr,
    _range = range
  }

  return setmetatable(self, {__index = MarkedRange})
end

function MarkedRange:update(range)
  self:unmark()
  self._range = range
  self:mark()
end

function MarkedRange:start()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.Ns.Range, self.start_mark, {})
end

function MarkedRange:end_()
  return api.nvim_buf_get_extmark_by_id(self.bufnr, Common.Ns.Range, self.end_mark, {})
end

function MarkedRange:range()
  return MarkedRange.combine_range(self:start(), self:end_())
end

function MarkedRange:is_in_range(row, col)
  return Utils.is_in_range(row, col, self:range())
end

function MarkedRange:is_marked()
  return self.start_mark and self.end_mark
end

function MarkedRange:mark()
  self.start_mark = api.nvim_buf_set_extmark(self.bufnr, Common.Ns.Range, self._range[1], self._range[2], {
    right_gravity = false
  })
  self.end_mark = api.nvim_buf_set_extmark(self.bufnr, Common.Ns.Range, self._range[3], self._range[4], {})
end

function MarkedRange:unmark()
  if self.end_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.Ns.Range, self.end_mark)
  end
  if self.start_mark then
    api.nvim_buf_del_extmark(self.bufnr, Common.Ns.Range, self.start_mark)
  end
end

function MarkedRange:is_empty()
  local range = self:range()

  return range[1] == range[3] and range[4] - range[2] == 1
end

function MarkedRange.get_inner_most(list, range, mapper)
  local last_result
  local last_range
  local row, col = unpack(range)

  mapper = mapper or Utils.identity

  for _, item in pairs(list) do
    local marked_range = mapper(item)

    if marked_range:is_in_range(row, col) then
      if not last_range
        or (last_range:is_in_range(unpack(marked_range:start()))
          and last_range:is_in_range(unpack(marked_range:end_()))) then
        last_range = marked_range
        last_result = item
      end
    end
  end

  return last_result, last_range
end

return MarkedRange
