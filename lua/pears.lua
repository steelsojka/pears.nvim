local Config = require "pears.config"
local Common = require "pears.common"
local Utils = require "pears.utils"
local Edit = require "pears.edit"
local PearTree = require "pears.pear_tree"
local Input = require "pears.input"
local Lang = require "pears.lang"
local api = vim.api

local M = {}

M.config = Config.get_default_config()
M.inputs_by_buf = Utils.make_buf_table(function(input)
  input:reset()
end)
M.trees_by_buf = Utils.make_buf_table()
M.state_by_buf = Utils.make_buf_table()

function M.setup(config_handler)
  M.config = Config.make_user_config(config_handler)

  vim.cmd [[au BufEnter * :lua require("pears").attach()]]
end

function M.is_attached(bufnr)
  local _, activated = pcall(api.nvim_buf_get_var, bufnr, Common.activated_buf_var)

  return activated == 1
end

function M.attach(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if M.is_attached(bufnr) then
    return
  end

  api.nvim_buf_set_var(bufnr, Common.activated_buf_var, 1)
  M.setup_buf_pairs(nil, {bufnr = bufnr, skip_on_exist = true})

  api.nvim_buf_set_keymap(
    bufnr,
    "i",
    "<BS>",
    string.format([[<Cmd>lua require("pears").handle_backspace(%d)<CR>]], bufnr),
    {silent = true})

  if M.config.expand_on_enter then
    api.nvim_buf_set_keymap(
      bufnr,
      "i",
      "<CR>",
      string.format([[<Cmd>lua require("pears").handle_return(%d)<CR>]], bufnr),
      {silent = true})
  end

  -- vim.cmd(string.format([[au FileType <buffer=%d> lua require("pears").setup_buf_pairs(nil, {bufnr = %d})]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertLeave <buffer=%d> lua require("pears").on_insert_leave(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertEnter <buffer=%d> lua require("pears").on_insert_enter(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertCharPre <buffer=%d> call luaeval("require('pears').handle_input(%d, _A)", v:char)]], bufnr, bufnr))
end

function M.handle_backspace(bufnr)
  local pear_tree, input = M.get_buf_tree(bufnr)

  if pear_tree then
    if M.config.remove_pair_on_inner_backspace then
      local open_leaf, close_leaf = pear_tree:get_wrapping_pair_at(bufnr)

      -- Remove the enclosed pair
      -- {|} -> |
      if open_leaf and close_leaf and M.config.remove_pair_on_inner_backspace then
        Edit.backspace(#open_leaf.open)
        Edit.delete(#close_leaf.close)
        input:reset()

        return
      end
    end

    if M.config.remove_pair_on_outer_backspace then
      local cursor = Utils.get_cursor()

      for i = 1, pear_tree.max_closer_len do
        local open_leaf, close_leaf = pear_tree:get_wrapping_pair_at(bufnr, {cursor[1], cursor[2] - i})

        -- Remove from the end of the pair
        -- NOTE: Does not support nested pairs
        -- {}| -> |
        if open_leaf and close_leaf and #close_leaf.close == i then
          Edit.backspace(#open_leaf.open + #close_leaf.close)
          input:reset()

          return
        end
      end
    end
  end

  -- input:step_back()
  Edit.backspace()
end

function M.handle_return(bufnr)
  if type(M.config.on_enter) == "function" then
    M.config.on_enter(function()
      M._handle_return(bufnr)
    end, Edit.enter)
  else
    M._handle_return(bufnr)
  end
end

function M._handle_return(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local before = Utils.get_surrounding_chars(bufnr)

  if before then
    local key = Config.get_escaped_key(before)
    local leaf = M.config.pairs[key]

    if leaf then
      local _, after = Utils.get_surrounding_chars(bufnr, nil, #leaf.close)

      if after == leaf.close then
        leaf.handle_return(bufnr)
        return
      end
    end
  end

  Edit.enter()
end

function M.on_insert_leave(bufnr)
  local _, input = M.get_buf_tree(bufnr)

  if not input then return end

  input:reset()
end

-- Note, this MAY cause performance issues if the trie pair tree
-- generation takes to long. So far it has not caused any issues.
-- This also is the event that detects what language we are in.
-- One known issue with this is if you have cross language boundaries
-- within the same insert mode session. Re-evaluate this IF it becomes a problem.
-- We would just need to switch which event triggers the generation.
function M.on_insert_enter(bufnr)
  local current_lang = Lang.get_current_lang(bufnr)
  local state = M.state_by_buf[bufnr]

  -- No need to regenerate if the lang hasn't changed.
  if not state or current_lang ~= state.lang then
    local pairs = state and state.pairs or nil

    M.setup_buf_pairs(pairs, { lang = current_lang, bufnr = bufnr })
  end
end

function M.handle_input(bufnr, char)
  local _, input = M.get_buf_tree(bufnr)

  if not input then return end

  input:_input(char)
end

function M.get_buf_tree(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  return M.trees_by_buf[bufnr], M.inputs_by_buf[bufnr]
end

function M.expand(bufnr)
  local _, input = M.get_buf_tree(bufnr)

  if not input then return end

  input:expand_wildcard()
end

function M.setup_buf_pairs(_pairs, opts)
  opts = opts or {}

  local bufnr = opts.bufnr or api.nvim_get_current_buf()
  local lang = opts.lang or api.nvim_buf_get_option(bufnr, 'ft')
  local included_pairs = {}
  local _, input = M.get_buf_tree(bufnr)

  if input then
    if opts.skip_on_exist then
      return
    end

    input:reset()
  end

  for key, pair in pairs(M.config.pairs) do
    if pair.should_include(lang) then
      included_pairs[key] = pair
    end
  end

  local pear_tree = PearTree.new(included_pairs)

  M.state_by_buf[bufnr] = {
    pairs = _pairs,
    lang = lang
  }
  M.trees_by_buf[bufnr] = pear_tree
  M.inputs_by_buf[bufnr] = Input.new(bufnr, pear_tree)
end

return M
