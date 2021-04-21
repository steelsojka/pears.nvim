local Utils = require "pears.utils"
local PearTree = require "pears.pear_tree"
local Edit = require "pears.edit"
local Config = require "pears.config"
local PairContext = require "pears.pair_context"
local MarkedRange = require "pears.marked_range"
local R = require "pears.rule"
local ts = require "vim.treesitter"
local api = vim.api

local Input = {}

function Input.new(bufnr, pear_tree, opts)
  opts = opts or {}

  local self = {
    bufnr = bufnr,
    tree = pear_tree,
    contexts = {},
    lang = opts.lang,
    pending_stack = {},
    expanded_contexts = {},
    closeable_contexts = Utils.KeyMap.new()}

  local success, parser = pcall(ts.get_parser, bufnr)

  if success then
    self.ts_parser = parser
  end

  return setmetatable(self, {__index = Input})
end

function Input:clear_contexts()
  for _, context in pairs(self.contexts) do
    context:destroy()
  end

  self.contexts = {}
  self.pending_stack = {}
  self.expanded_contexts = {}
  self.closeable_contexts:reset()
end

function Input:reset()
  self:clear_contexts()
end

function Input:set_tree(tree)
  self:reset()
  self.tree = tree
end

function Input:_destroy_context(context)
  self.contexts[context.id] = nil
  context:destroy()
end

function Input:expand(char)
  local pending = self.pending_stack[1]

  if pending then
    local did_expand = self:_expand_context(pending, char)

    if did_expand then
      return true, pending
    end

    return false, pending
  end

  return false
end

function Input:_input(char)
  local key = PearTree.make_key(char)
  local did_close_context = false
  local current_context

  if self.closeable_contexts:get(key) then
    local row, col = unpack(Utils.get_cursor())

    for _, closeable_context in ipairs(self.closeable_contexts:get(key)) do
      local end_row, end_col = unpack(closeable_context.range:end_())

      -- End of context "test|"
      if col == end_col - 1 and row == end_row then
        -- Move cursor right "test"|
        -- This will still move the current pending context forward.
        Edit.prevent_input()
        vim.schedule(Edit.right)
        did_close_context = true
        break
      end
    end
  end

  -- Scheduling this will allow for the character to get inserted.
  -- This means indentation will be applied prior to us computed expansion.
  vim.schedule(function()
    local pop_count = 0
    local did_step = false
    local row, col = unpack(Utils.get_cursor())

    -- We moved forward, so move the cursor forward one.
    if did_close_context then
      col = col + 1
    end

    for _, context in ipairs(self.pending_stack) do
      local step_result = context:step_forward(char, {row, col})

      if step_result.did_step or not step_result.done then
        did_step = step_result.did_step
        current_context = context
        break
      else
        pop_count = pop_count + 1
      end
    end

    for i = 1, pop_count, 1 do
      table.remove(self.pending_stack, 1)
    end

    if not did_step and not did_close_context then
      if self.tree.openers.branches[key] then
        -- We started a new pair context
        local new_context = PairContext.new(self.tree.openers, {row, col - 1, row, col}, self.bufnr)

        self.contexts[new_context.id] = new_context
        table.insert(self.pending_stack, 1, new_context)
        new_context:step_forward(char, {row, col})
        new_context.range:mark()
      end
    end

    self:expand(char)
  end)
end

function Input:expand_wildcard()
  local next_wildcard, index = Utils.find(function(context)
    return context.is_wildcard
  end, self.pending_stack)

  if next_wildcard then
    local did_expand, context = self:expand(nil)

    if did_expand
      and context
      and context.leaf
      and context.leaf.is_wildcard
      and context == self.pending_stack[1]
    then
      table.remove(self.pending_stack, 1)
    end
  end

  return did_expand, context
end

function Input:_handle_expansion(args)
  if Utils.is_func(args.leaf.handle_expansion) then
    args.leaf.handle_expansion(args)

    return
  end

  if args.leaf.is_wildcard then
    Input:_handle_wildcard_expansion(args)
  else
    Input:_handle_simple_expansion(args)
  end
end

function Input:_make_event_args(char, context, leaf)
  return {
    char = char,
    context = context,
    leaf = leaf,
    lang = self.lang,
    cursor = Utils.get_cursor(),
    bufnr = self.bufnr,
    input = self
  }
end

function Input:_expand_context(context, char)
  local leaf = context.leaf

  if not leaf then return false end

  local event = self:_make_event_args(char, context, leaf)

  if R.pass(leaf.expand_when(event)) then
    local expanded = false
    local should_expand = true

    if R.pass(leaf.should_expand(event)) then
      if leaf.is_wildcard then
        local row, col = unpack(Utils.get_cursor())
        local expanded_context = self:_get_context_at_position(self.expanded_contexts, {row, col + 1})

        -- If we are in another context we don't want to expand any wildcards...
        if expanded_context
          and expanded_context ~= context
          and context.range:is_in_range(unpack(expanded_context.range:start()))
        then
          return false
        end
      end

      if should_expand then
        self:_handle_expansion(event)

        if #leaf.close == 1 then
          self.closeable_contexts:set(leaf.close_key, context)
        end

        self.expanded_contexts[context.id] = context
        expanded = true
      end
    end

    if context:at_end() then
      table.remove(self.pending_stack, 1)
    end

    return expanded
  end

  return false
end

function Input:_is_in_context(context)
  return context == self:_get_context_at_position(Utils.get_cursor())
end

function Input:_get_context_at_position(contexts, position)
  return MarkedRange.get_inner_most(contexts, position, function(v) return v.range end)
end

function Input:_handle_wildcard_expansion(args)
  local row, col = unpack(args.cursor)
  local line = table.concat(api.nvim_buf_get_lines(args.bufnr, row, row + 1, false), "")
  local start_row, start_col, end_row, end_col = unpack(args.context.range:range())

  -- Determine if we need to fill in any closing characters for the opener.
  -- For example, if we triggered the expansion without entering in a character (through a keybinding),
  -- then we need to see if we need to insert any closers "<di|v" -> "<div></div>"
  local closing_opener_chars = {}
  local before_end = Utils.get_surrounding_chars(args.bufnr, {end_row, end_col}, #args.leaf.next_chars, 0)
  local char_index = #args.leaf.next_chars

  for index = #args.leaf.next_chars, 1, -1 do
    local expected_char = args.leaf.next_chars[index]
    local actual_char = string.sub(before_end, index, index)

    if expected_char == actual_char then
      break
    end

    table.insert(closing_opener_chars, 1, expected_char)
  end

  local start_offset = #args.leaf.prev_chars
  local end_offset = #args.leaf.next_chars - #closing_opener_chars
  local line_end_col = #line - #args.leaf.next_chars
  local content_lines = Utils.get_content_from_range(args.bufnr, {start_row, start_col + start_offset, end_row, end_col - end_offset})
  local content = table.concat(content_lines, "")
  local wild_content = Config.resolve_capture(args.leaf.capture_content, content)
  local prefix = table.concat(args.leaf.prev_chars)
  local suffix = table.concat(args.leaf.next_chars)
  local tail_prefix, tail_suffix = string.match(args.leaf.unescaped_close, "(.*)*(.*)")

  api.nvim_win_set_cursor(0, {end_row + 1, end_col})

  if #closing_opener_chars > 0 then
    Edit.insert(table.concat(closing_opener_chars))
  end

  Edit.insert(tail_prefix .. wild_content .. tail_suffix)
  api.nvim_win_set_cursor(0, {end_row + 1, end_col + #closing_opener_chars})
end

function Input:_handle_simple_expansion(args)
  local range = args.context.range:range()

  api.nvim_win_set_cursor(0, {range[1] + 1, range[2]})
  Edit.delete(range[4] - range[2])
  Edit.insert(args.leaf.unescaped_open .. args.leaf.unescaped_close)
  Edit.left(#args.leaf.unescaped_close)
end

return Input
