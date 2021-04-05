local Config = require "pears.config"
local Common = require "pears.common"
local Context = require "pears.context"
local Utils = require "pears.utils"
local api = vim.api

local M = {}

local namespace = Common.namespace

M.config = Config.get_default_config()
M.contexts_by_buf = {}

function M.setup(config_handler)
  M.config = Config.make_user_config(config_handler)

  vim.cmd [[au BufEnter * :lua require("pears").attach()]]
end

function M.attach(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if M.contexts_by_buf[bufnr] then
    return
  end

  M.contexts_by_buf[bufnr] = {}

  api.nvim_buf_attach(bufnr, false, {
    on_detach = function()
      M.contexts_by_buf[bufnr] = nil
    end
  })

  for key, entry in pairs(M.config.pairs) do
    api.nvim_buf_set_keymap(
      bufnr,
      "i",
      entry.open,
      string.format([[<Cmd>lua require("pears").expand_pair("%s", %s)<CR>]], key, bufnr),
      {noremap = true, silent = true})

    if entry.open ~= entry.close then
      api.nvim_buf_set_keymap(
        bufnr,
        "i",
        entry.close,
        string.format([[<Cmd>lua require("pears").expand_pair("%s", %s, true)<CR>]], key, bufnr),
        {noremap = true, silent = true})
    end
  end

  api.nvim_buf_set_keymap(
    bufnr,
    "i",
    "<BS>",
    string.format([[<Cmd>lua require("pears").handle_backspace(%d)<CR>]], bufnr),
      {noremap = true, silent = true})

  vim.cmd(string.format([[au CursorMoved,CursorMovedI <buffer=%d> lua require("pears").check_context(%d)]], bufnr, bufnr))
end

function M.get_pair_entry(key)
  return M.config.pairs[key]
end

function M.get_buf_contexts(bufnr)
  return M.contexts_by_buf[bufnr] or {}
end

function M.get_context(bufnr, row, col, key)
  local last_result

  for _, context in ipairs(M.get_buf_contexts(bufnr)) do
    if (not key or context.key == key) and context:is_in_range(row, col) then
      if not last_result
        or (last_result:is_in_range(unpack(context:start()))
          and last_result:is_in_range(unpack(context:end_()))) then
        last_result = context
      end
    end
  end

  return last_result
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
  local pair_contexts = M.get_buf_contexts(bufnr)

  if vim.tbl_isempty(pair_contexts) then
    return
  end

  local row, col = unpack(api.nvim_win_get_cursor(0))
  local contexts = {}

  row = row - 1

  for _, context in ipairs(pair_contexts) do
    if context:is_in_range(row, col) then
      table.insert(contexts, context)
    else
      context:destroy()
    end
  end

  M.contexts_by_buf[bufnr] = contexts
end

local function backspace()
  vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<BS>", true, false, true), "n", true)
end

local function delete()
  vim.api.nvim_feedkeys(api.nvim_replace_termcodes("<Del>", true, false, true), "n", true)
end

function M.handle_backspace(bufnr)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local context = M.get_context(bufnr, row - 1, col)

  if context and context:is_empty() then
    backspace()
    delete()
    remove_context(bufnr, context)

    return
  end

  local before, after = Utils.get_wrapped_chars(bufnr)

  -- If we aren't in a matching context, check our characters old school.
  if before and after then
    local key = Config.get_escaped_key(before)
    local pair_entry = M.config.pairs[key]

    if pair_entry and pair_entry.close == after then
      backspace()
      delete()

      return
    end
  end

  backspace()
end

function M.expand_pair(key, bufnr, explicit_close)
  local entry = M.get_pair_entry(key)
  local row, col = unpack(api.nvim_win_get_cursor(0))
  local can_close = explicit_close or entry.open == entry.close
  local is_closing = explicit_close
  local is_closed = false

  if can_close then
    local context = M.get_context(bufnr, row - 1, col, key)

    if context then
      local end_row, end_col = unpack(context:end_())

      if row - 1 == end_row and col == end_col then
        is_closing = true
        is_closed = true
      end
    end
  end

  if is_closing then
    if is_closed then
      api.nvim_win_set_cursor(0, {row, col + #entry.close})
    else
      api.nvim_put({entry.close}, "c", false, true)
    end
  else
    local pad_string = string.rep(" ", entry.padding)
    local open = entry.open .. pad_string
    local close = pad_string .. entry.close

    api.nvim_put({open .. close}, "c", false, false)
    api.nvim_win_set_cursor(0, {row, col + #open})

    local contexts = M.get_buf_contexts(bufnr)
    local context = Context.new(bufnr, key, {row - 1, col, row - 1, col + #open})

    table.insert(contexts, context)
  end
end

return M
