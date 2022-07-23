local Config = require "pears.config"
local Common = require "pears.common"
local Utils = require "pears.utils"
local Edit = require "pears.edit"
local PearTree = require "pears.pear_tree"
local Input = require "pears.input"
local Lang = require "pears.lang"
local R = require "pears.rule"
local Buffer = require "pears.buffer"
local Ui = require "pears.ui"
local Pointer = require "pears.pointer"
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

  if Utils.is_func(M.config.disable) and M.config.disable(bufnr) then
    return
  end

  -- Global filetype disabled list
  if Utils.is_table(M.config.disabled_filetypes)
    and vim.tbl_contains(
      M.config.disabled_filetypes,
      api.nvim_buf_get_option(bufnr, "filetype"))
  then
    return
  end

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

  vim.cmd(string.format([[au InsertLeave <buffer=%d> lua require("pears").on_insert_leave(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertEnter <buffer=%d> lua require("pears").on_insert_enter(%d)]], bufnr, bufnr))
  vim.cmd(string.format([[au InsertCharPre <buffer=%d> call luaeval("require('pears').handle_input(%d, _A)", v:char)]], bufnr, bufnr))
end

function M.handle_backspace(bufnr)
  local pear_tree, input = M.get_buf_tree(bufnr)

  if pear_tree then
    -- Remove the enclosed pair
    -- {|} -> |
    if M.config.remove_pair_on_inner_backspace then
      local pos = Utils.get_cursor()
      local line = api.nvim_buf_get_lines(bufnr, pos[1], pos[1] + 1, false)[1] or ""
      local pear = Buffer.get_containing_pair {
        tree = pear_tree,
        bufnr = bufnr,
        position = pos,
        range = {
          pos[1],
          math.max(pos[2] - pear_tree.reverse_openers.max_len, 0),
          pos[1],
          math.min(pos[2] + pear_tree.closers.max_len, #line)
        }
      }

      if pear and Utils.is_range_empty(pear.inner_range) then
        Edit.backspace(#pear.leaf.opener.chars)
        Edit.delete(#pear.leaf.closer.chars)
        input:reset()

        return
      end
    end

    -- Remove from the end of the pair
    -- NOTE: Does not support nested pairs
    -- {}| -> |
    if M.config.remove_pair_on_outer_backspace then
      local pos = Utils.get_cursor()
      local iter = Buffer.iter_pairs {
        bufnr = bufnr,
        open_trie = pear_tree.reverse_openers,
        close_trie = pear_tree.reverse_closers,
        direction = Pointer.Direction.Backwards,
        range = {
          pos[1],
          math.max(pos[2] - 1 - (pear_tree.reverse_openers.max_len + pear_tree.reverse_closers.max_len), 0),
          pos[1],
          pos[2]
        }
      }

      for _, pear in iter do
        if pear
          and pear.range[3] == pos[1]
          and pear.range[4] == pos[2] - 1
          and Utils.is_range_empty(pear.inner_range)
        then
          Edit.backspace(#pear.leaf.opener.chars + #pear.leaf.closer.chars)
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
    local keys = M.config.on_enter(function()
      M._handle_return(bufnr)
    end, Edit.enter)

    if Utils.is_string(keys) then
      api.nvim_feedkeys(keys, "n", true)
    end
  else
    M._handle_return(bufnr)
  end
end

function M._handle_return(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  local tree, input = M.get_buf_tree(bufnr)

  if input and tree then
    local before = Buffer.get_immediate_pair {
      trie = tree.reverse_openers,
      bufnr = bufnr,
      direction = Pointer.Direction.Backwards
    }

    if before and before.leaf then
      local after = Buffer.get_immediate_pair {
        trie = tree.closers,
        bufnr = bufnr,
        direction = Pointer.Direction.Forward
      }

      local pair_closed = (after and after.leaf and after.leaf.key == before.leaf.key)

      -- If there isn't a closing pair, try to expand to handle the case
      -- where the pair has been configured to expand on enter.
      if not pair_closed then
        pair_closed = input:expand(nil, Input.VirtualKey.ENTER)
      end

      if pair_closed then
        if R.pass(before.leaf.should_return {
          leaf = before.leaf,
          input = input,
          lang = input.lang,
          bufnr = bufnr,
          cursor = Utils.get_cursor()
        }) then
          before.leaf.handle_return(bufnr)
          return
        end
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

    M.setup_buf_pairs(pairs, {lang = current_lang, bufnr = bufnr})
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
  M.inputs_by_buf[bufnr] = Input.new(bufnr, pear_tree, {lang = lang})
end

function M.iter_buf_pairs(bufnr)
  local tree = M.get_buf_tree(bufnr)

  if not tree then return end

  return Buffer.iter_pairs {
    range = Utils.get_buf_range(bufnr),
    bufnr = bufnr,
    direction = Pointer.Direction.Forward,
    open_trie = tree.openers,
    close_trie = tree.closers
  }
end

function M.get_containing_pair(bufnr)
  local tree = M.get_buf_tree(bufnr)

  if not tree then return end

  return Buffer.get_containing_pair {
    bufnr = bufnr,
    tree = tree
  }
end

function M.highlight_containing_pair(bufnr, timeout)
  local pear = M.get_containing_pair(bufnr)

  M.clear_pair_highlights(bufnr)

  if pear then
    Ui.highlight_pair_results(bufnr, {pear}, timeout)
  end
end

function M.highlight_buf_pairs(bufnr, timeout)
  Ui.clear_pair_highlights(bufnr)
  Ui.highlight_pair_results(bufnr, M.iter_buf_pairs(bufnr), timeout)
end

function M.clear_pair_highlights(bufnr)
  Ui.clear_pair_highlights(bufnr)
end

return M
