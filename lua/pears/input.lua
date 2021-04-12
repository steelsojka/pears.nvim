local Utils = require "pears.utils"
local PearTree = require "pears.pear_tree"
local Context = require "pears.context"
local Edit = require "pears.edit"
local Config = require "pears.config"
local PairContext = require "pears.pair_context"
local api = vim.api

local Input = {}

function Input.new(bufnr, pear_tree, opts)
  opts = opts or {}

  local self = {
    bufnr = bufnr,
    tree = pear_tree,
    contexts = {},
    wildcard_start = nil,
    pending_stack = {},
    current_context = nil,
    current_branch = pear_tree.openers
  }

  return setmetatable(self, {__index = Input})
end

function Input:get_context(row, col, key)
  local last_result

  for _, context in ipairs(self.contexts) do
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

function Input:get_contexts()
  return self.contexts
end

function Input:remove_context(context)
  local removed = Utils.pull(self.contexts, context, function(a, b) a:equals(b) end)

  if removed then
    if removed == self.current_context then
      self.current_context = nil
    end

    removed:destroy()
  end
end

function Input:clear_contexts()
  for _, context in ipairs(self.contexts) do
    context:destroy()
  end

  self.contexts = {}
end

function Input:_make_context(leaf, start, end_)
  return Context.new(self.bufnr, leaf.key, Context.combine_range(start, end_))
end

function Input:step_back()
  if self.current_branch and self.current_branch.parent then
    self.current_branch = self.current_branch.parent
  else
    self:reset()
  end
end

function Input:_input(char)
  local key = PearTree.make_key(char)
  local row, col = unpack(api.nvim_win_get_cursor(0))

  local did_expand, context = self:expand(char)

  if did_expand then
    return
  elseif context then
    context:step_forward(key)
  end

  -- TODO: Check closers

  if not self.tree.branches[key] then return end

  -- We started a new pair context

  local new_context = PairContext.new(self.tree)

  table.insert(new_context, 1)
  new_context:step_forward(char)
  self:expand(char)
end

function Input:expand(char)
  local pending = self.pending_stack[1]

  if pending then
    local did_expand = self._expand_context(pending, char)

    if did_expand then
      return true, pending
    end

    return false, pending
  end

  return false
end

function Input:_handle_expansion(leaf, context)
  if Utils.is_func(leaf.handle_expansion) then
    leaf.handle_expansion({
      input = self,
      leaf = leaf,
      context = context,
      bufnr = self.bufnr
    })

    return
  end

  if leaf.is_wildcard then
    Input:_handle_wildcard_expansion(leaf, context)
  else
    Input:_handle_simple_expansion(leaf, context)
  end
end

function Input:_expand_context(context, char)
  local args = {
    char = char,
    context = context,
    bufnr = self.bufnr,
    input = self
  }

  local leaf = context:get_current_leaf()

  if leaf and leaf.expand_when(args) then
    if leaf.should_expand(args) then
      self:_handle_expansion(pending_leaf, context)

      return true
    end

    table.remove(self.pending_stack, 1)
  end

  return false
end

function Input:expand(char)
  local pending = self.pending_stack[1]

  if pending then
    local args = {
      char = char,
      bufnr = self.bufnr,
      input = self
    }
    local pending_leaf = pending:get_current_leaf()

    if pending_leaf and pending_leaf.expand_when(args) and pending_leaf.should_expand(args) then
      self:handle_expansion(pending_leaf)
      table.remove(self.pending_stack, 1)

      return true
    end
  end

  return false
end

function Input:input(char)
  local key = PearTree.make_key(char)
  local row, col = unpack(api.nvim_win_get_cursor(0))

  -- Next branch in the tree. If it's nil then we either are entering a new sequence
  -- or just entering regular input.
  local next_branch = self.current_branch and self.current_branch.branches[key]

  local closer_entry = self.tree.closers:query(char)

  -- If this is a closer (single-char), check if we are part of a context with this entry.
  if closer_entry then
    local containing_context = self:get_context(row - 1, col, closer_entry.key)

    if containing_context then
      -- If we are in a corresponding context and the next char is a closer...
      -- then don't insert anything and move the cursor right one.
      -- NOTE: This only works for single character closers.
      local _, next_char = Utils.get_surrounding_chars(self.bufnr, nil, 1)

      if next_char == closer_entry.close then
        -- Don't insert any char
        vim.cmd [[let v:char = ""]]

        if self.current_wildcard and self:should_expand_wildcard(next_char) then
          self:expand_wildcard(next_char, 1)
          self:reset()
        else
          -- If there is also another branch with this key, we want to make
          -- sure to move the current branch pointer down.
          if next_branch then
            self.current_branch = next_branch
          end

          vim.schedule(Edit.right)
        end

        return
      end
    end
  end

  if self.current_wildcard then
    if self:should_expand_wildcard(char) then
      vim.cmd [[let v:char = ""]]
      self:expand_wildcard(char)
      self:reset()
    end

    return
  end

  -- If we shouldn't expand based on the callback then reset and abort.
  if next_branch
    and next_branch.leaf
    and not next_branch.leaf.should_expand({
      bufnr = self.bufnr,
      pair = next_branch.leaf,
      input = self
    })
  then
    self:reset()
    return
  end

  -- This would mean a new sequence, so we check the char against the root tree.
  if not next_branch then
    if self.current_branch.wildcard and not self:should_expand_wildcard(char, self.current_branch.wildcard) then
      self.current_wildcard = self.current_branch.wildcard
      self.wildcard_start = col
    else
      self:reset()
      next_branch = self.current_branch and self.current_branch.branches[key]
    end
  end

  -- If nothing here then we are entering just regular input.
  if not next_branch then return end

  -- Queue of edit commands that we will execute when nvim is ready.
  local queue = Edit.Queue.new()

  -- If this branch has a leaf pair, we want to expand it.
  if next_branch.leaf then
    local start
    local leaf = next_branch.leaf

    -- Empty wildcard match <*></*> -> we entered <>
    -- This wouldn't get flagged a wildcard yet until now, so
    -- just set the wildcard state and act as if we input the character again.
    if leaf.is_wildcard then
      self.current_wildcard = leaf
      self.wildcard_start = col
      self:input(char)
      return
    end

    if not row or not col then
      row, col = unpack(api.nvim_win_get_cursor(0))
    end

    -- If there is a current context that we have previously expanded, we
    -- want to remove the previous leafs closer and use this leafs closer.
    -- For example HTML "<" ">" would be the current context and "<!--" "-->" would
    -- replace the previous leaf.
    if self.current_context then
      local prev_context = self.current_context

      start = prev_context:start()

      local _end = prev_context:end_()

      queue:add(function(_start, _end_col, _leaf)
        -- Set the cursor back to the beginning of the context area
        api.nvim_win_set_cursor(0, {_start[1] + 1, _start[2]})
        -- Delete all text to either the cursor or end context area (inclusive), whichever is larger
        Edit.delete(_end_col - _start[2] + 1)
        -- Insert the new open
        Edit.insert(_leaf.open)
      end, {start, math.max(col, _end[2] + 1), leaf})

      self:remove_context(prev_context)
    else
      -- If we don't have a current_context then this is a new sequence,
      -- so start the range at the cursor.
      start = {row - 1, col}
    end

    local end_ = {row - 1, col + #leaf.close}

    -- Insert the closer
    queue:add(Edit.insert, {leaf.close})
    -- Reset the cursor position
    queue:add(Edit.left, {#leaf.close})

    local new_context = self:_make_context(leaf, start, end_)

    -- Queue the context to add extmarks... if this fails we don't want to throw an error.
    -- Instead just remove the context and move on.
    queue:add(function()
      local success = pcall(function() new_context:mark() end)

      if not success then
        self:remove_context(new_context)
      end
    end)

    table.insert(self.contexts, new_context)

    -- If there are more branches after this leaf then track it for additional input.
    if not vim.tbl_isempty(next_branch.branches) then
      self.current_context = new_context
    end
  end

  if not vim.tbl_isempty(next_branch.branches) then
    self.current_branch = next_branch
  elseif next_branch.wildcard then
    self.current_wildcard = next_branch.wildcard
  else
    -- Reset everything if there are no more branches.
    self:reset()
  end

  -- Execute our edits and markings
  vim.schedule(function() queue:execute() end)
end

function Input:should_expand_wildcard(char, wildcard)
  wildcard = wildcard or self.current_wildcard

  if not wildcard then return true end

  if wildcard.should_expand then
    return wildcard.should_expand({
      char = char,
      bufnr = self.bufnr,
      pair = wildcard,
      input = self
    })
  end

  return self:_should_expand_wildcard(wildcard, char)
end

function Input:_should_expand_wildcard(wildcard, char)
  return wildcard.next_chars[1] == char
end

function Input:_handle_wildcard_expansion(leaf, context)
end

function Input:_handle_simple_expansion(leaf, context)
end

function Input:expand_wildcard(char, col_offset)
  if not self.current_wildcard then return end

  local _, current_col = unpack(Utils.get_cursor())

  if not col_offset then
    if self.current_context then
      local _, context_col = unpack(self.current_context:end_())

      col_offset = context_col - current_col + 1
    else
      col_offset = 0
    end
  end

  local args = {
    char = char,
    bufnr = self.bufnr,
    offset = col_offset,
    wildcard = self.current_wildcard,
    wildcard_start = self.wildcard_start
  }

  if Utils.is_func(self.current_wildcard.handle_expansion) then
    self.current_wildcard.handle_expansion(args)
  else
    self:_expand_wildcard(args)
  end

  self:reset()
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

function Input:reset()
  self.current_branch = self.tree.openers
  self.current_context = nil
  self.current_wildcard = nil
  self.wildcard_start = nil
end

return Input
