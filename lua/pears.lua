local Config = require "pears.config"
local Common = require "pears.common"
local Context = require "pears.context"
local Utils = require "pears.utils"
local Edit = require "pears.edit"
local PearTree = require "pears.pear_tree"
local Input = require "pears.input"
local api = vim.api

local M = {}

M.config = Config.get_default_config()
M.contexts_by_buf = Utils.make_buf_table()
M.inputs_by_buf = Utils.make_buf_table(function(input)
  input:reset()
end)
M._pear_tree = PearTree.new()

function M.setup(config_handler)
  M.config = Config.make_user_config(config_handler)
  M._pear_tree:from_config(M.config.pairs)

  vim.cmd [[au BufEnter * :lua require("pears").attach()]]
end

function M.attach(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local _, activated = pcall(api.nvim_buf_get_var, bufnr, Common.activated_buf_var)

  if activated == 1 then
    return
  end

  api.nvim_buf_set_var(bufnr, Common.activated_buf_var, 1)
  M.contexts_by_buf[bufnr] = {}
  M.inputs_by_buf[bufnr] = Input.new(bufnr, M._pear_tree, {})

  api.nvim_buf_set_keymap(
    bufnr,
    "i",
    "<BS>",
    string.format([[<Cmd>lua require("pears").handle_backspace(%d)<CR>]], bufnr),
      {noremap = true, silent = true})

  vim.cmd(string.format([[au CursorMoved <buffer=%d> lua require("pears").check_context(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertCharPre <buffer=%d> call luaeval("require('pears').handle_input(%d, _A)", v:char)]], bufnr, bufnr))
end

function M.get_pair_entry(key)
  return M.config.pairs[key]
end

function M.get_buf_contexts(bufnr)
  return M.contexts_by_buf[bufnr] or {}
end

local function remove_context(bufnr, context)
  local index
  local pair_contexts = M.get_buf_contexts(bufnr)

  for i, _context in ipairs(pair_contexts) do
    if context:equals(_context) then
      index = i
      break
    end
  end

  if index then
    context:destroy()
    table.remove(pair_contexts, index)
  end
end

function M.check_context(bufnr)
  local input = M.inputs_by_buf[bufnr]
  local contexts = input:get_contexts()

  if vim.tbl_isempty(contexts) then
    return
  end

  local row, col = unpack(api.nvim_win_get_cursor(0))

  row = row - 1

  input:filter_contexts(function(context)
    return context:is_in_range(row, col)
  end)
end

function M.handle_backspace(bufnr)
  local input = M.inputs_by_buf[bufnr]
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local context = input:get_context(row - 1, col)

  if context and context:is_empty() then
    Edit.backspace()
    Edit.delete()
    input:remove_context(context)

    return
  end

  local before, after = Utils.get_surrounding_chars(bufnr)

  -- If we aren't in a matching context, check our characters old school.
  if before and after then
    local key = Config.get_escaped_key(before)
    local pair_entry = M.config.pairs[key]

    if pair_entry and pair_entry.close == after then
      Edit.backspace()
      Edit.delete()

      return
    end
  end

  Edit.backspace()
end

function M.handle_input(bufnr, char)
  local input = M.inputs_by_buf[bufnr]

  if not input then return end

  input:input(char)
end

return M
