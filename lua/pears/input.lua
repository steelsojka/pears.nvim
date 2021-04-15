local Utils = require "pears.utils"
local PearTree = require "pears.pear_tree"
local Edit = require "pears.edit"
local Config = require "pears.config"
local PairContext = require "pears.pair_context"
local MarkedRange = require "pears.marked_range"
local api = vim.api

local Input = {}

function Input.new(bufnr, pear_tree, opts)
  opts = opts or {}

  local self = {
    bufnr = bufnr,
    tree = pear_tree,
    contexts = {},
    pending_stack = {},
    expanded_contexts = {},
    closeable_contexts = Utils.KeyMap.new()
  }

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

function Input:_destroy_context(context)
  self.contexts[context.id] = nil
  context:destroy()
end

function Input:expand(char, queue)
  local pending = self.pending_stack[1]

  if pending then
    local did_expand = self:_expand_context(pending, char, queue)

    if did_expand then
      return true, pending
    end

    return false, pending
  end

  return false
end

function Input:_pop_pending()
  local context = self.pending_stack[1]

  if context then
    self:_destroy_context(context)
    table.remove(self.pending_stack, 1)
  end
end

function Input:_input(char)
  local key = PearTree.make_key(char)
  local row, col = unpack(Utils.get_cursor())
  local queue = Edit.Queue.new(true)
  local did_close_context = false
  local current_context

  if self.closeable_contexts:get(key) then
    for _, closeable_context in ipairs(self.closeable_contexts:get(key)) do
      local _, end_col = unpack(closeable_context.range:end_())

      -- End of context "test|"
      if col == end_col - 1 then
        -- Move cursor right "test"|
        -- This will still move the current pending context forward.
        Edit.prevent_input()
        queue:add(Edit.right)
        did_close_context = true
        break
      end
    end
  end

  local pop_count = 0
  local did_step = false

  for _, context in ipairs(self.pending_stack) do
    local step_result = context:step_forward(char)

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
      local new_context = PairContext.new(self.tree.openers, {row, col, row, col + 1}, self.bufnr)

      self.contexts[new_context.id] = new_context
      table.insert(self.pending_stack, 1, new_context)
      new_context:step_forward(char)
      queue:add(function() new_context.range:mark() end)
    end
  end

  self:expand(char, queue)
  queue:execute()
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

function Input:_make_event_args(char, context)
  return {
    char = char,
    context = context,
    bufnr = self.bufnr,
    input = self
  }
end

function Input:_expand_context(context, char, queue)
  local args = self:_make_event_args(char, context)
  local leaf = context.leaf

  if leaf and Config.resolve_matcher_event(leaf.expand_when, args, true) then
    local expanded = false
    local should_expand = true

    if leaf.should_expand(args) then
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
        local args = {
          input = self,
          leaf = leaf,
          char = char,
          cursor = Utils.get_cursor(),
          context = context,
          bufnr = self.bufnr
        }

        queue:add(function(_args) self:_handle_expansion(_args) end, {args})

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
  local start_offset = #args.leaf.prev_chars
  local end_offset = #args.leaf.next_chars
  local line_end_col = #line - #args.leaf.next_chars
  local content_lines = Utils.get_content_from_range(args.bufnr, {start_row, start_col + start_offset, end_row, end_col - end_offset})
  local content = table.concat(content_lines, "")
  local wild_content = Config.resolve_capture(args.leaf.capture_content, content)
  local prefix = table.concat(args.leaf.prev_chars)
  local suffix = table.concat(args.leaf.next_chars)
  local tail_prefix, tail_suffix = string.match(args.leaf.close, "(.*)*(.*)")

  vim.schedule(function()
    api.nvim_win_set_cursor(0, {end_row + 1, end_col})
    Edit.insert(tail_prefix .. wild_content .. tail_suffix)
    api.nvim_win_set_cursor(0, {end_row + 1, end_col - 1})
  end)
end

function Input:_handle_simple_expansion(args)
  local range = args.context.range:range()

  api.nvim_win_set_cursor(0, {range[1] + 1, range[2]})
  Edit.delete(range[4] - range[2])
  Edit.insert(args.leaf.open .. args.leaf.close)
  Edit.left(#args.leaf.close)
end

function Input:_expand_wildcard(args)
  local row, col = unpack(Utils.get_cursor())
  local line = api.nvim_buf_get_lines(args.bufnr, row, row + 1, false)[1] or ""
  local content_to_cursor = string.sub(line, args.wildcard_start + 1, col)
  local wild_content = Config.resolve_capture(args.wildcard.capture_content, content_to_cursor)
  local prefix = table.concat(args.wildcard.prev_chars)
  local suffix = table.concat(args.wildcard.next_chars)
  local tail_prefix, tail_suffix = string.match(args.wildcard.close, "(.*)*(.*)")
  local begin_col = args.wildcard_start - #args.wildcard.prev_chars

  vim.schedule(function()
    api.nvim_win_set_cursor(0, {row + 1, begin_col})
    Edit.delete(#args.wildcard.prev_chars + #content_to_cursor + #args.wildcard.next_chars - 1)
    Edit.insert(prefix .. content_to_cursor .. suffix .. tail_prefix .. wild_content .. tail_suffix)
    Edit.left(#tail_suffix + #wild_content + #tail_prefix)
  end)
end

return Input
