local Common = require "pears.common"
local Utils = require "pears.utils"
local api = vim.api

local Context = {}

function Context.new(bufnr, key, range)
  local start_row, start_col, end_row, end_col = unpack(range)

  local self = {
    bufnr = bufnr,
    key = key,
    raw_range = range,
    start_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, start_row, start_col, {}),
    end_mark = api.nvim_buf_set_extmark(bufnr, Common.namespace, end_row, end_col, {})
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
  local start_row, start_col = unpack(self:start())
  local end_row, end_col = unpack(self:end_())

  return {start_row, start_col, end_row, end_col}
end

function Context:is_in_range(row, col)
  return Utils.is_in_range(row, col, self:range())
end

function Context:destroy()
  api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.start_mark)
  api.nvim_buf_del_extmark(self.bufnr, Common.namespace, self.end_mark)
end

function Context:is_empty()
  local range = self:range()

  return range[1] == range[3] and range[4] - range[2] == 1
end

function Context:equals(context)
  return self.start_mark == context.start_mark and self.end_mark == context.end_mark
end

return Context
