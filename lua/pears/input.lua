local Utils = require "pears.utils"
local PearTree = require "pears.pear_tree"
local Context = require "pears.context"
local Edit = require "pears.edit"
local api = vim.api

local Input = {}

function Input.new(bufnr, pear_tree, opts)
  opts = opts or {}

  local self = {
    bufnr = bufnr,
    tree = pear_tree,
    contexts = {},
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

function Input:input(char)
  local key = PearTree.make_key(char)
  local row, col

  -- Next branch in the tree. If it's nil then we either are entering a new sequence
  -- or just entering regular input.
  local next_branch = self.current_branch and self.current_branch.branches[key]

  -- If we shouldn't expand based on the callback then reset and abort.
  if next_branch
    and next_branch.leaf
    and not next_branch.leaf.should_expand(self.bufnr, next_branch.leaf, self)
  then
    self:reset()
    return
  end

  local closer_entry = self.tree.closers:query(char)

  -- If this is a closer (single-char), check if we are part of a context with this entry.
  if closer_entry then
    row, col = unpack(api.nvim_win_get_cursor(0))

    local containing_context = self:get_context(row - 1, col, closer_entry.key)

    if containing_context then
      -- If we are in a corresponding context and the next char is a closer...
      -- then don't insert anything and move the cursor right one.
      -- NOTE: This only works for single character closers.
      local _, next_char = Utils.get_surrounding_chars(self.bufnr, 1)

      if next_char == closer_entry.close then
        -- If there is also another branch with this key, we want to make
        -- sure to move the current branch pointer down.
        if next_branch then
          self.current_branch = next_branch
        end

        vim.cmd [[let v:char = ""]]
        vim.schedule(Edit.right)
        return
      end
    end
  end

  -- This would mean a new sequence, so we check the char against the root tree.
  if not next_branch then
    self:reset()
    next_branch = self.current_branch and self.current_branch.branches[key]
  end

  -- If nothing here then we are entering just regular input.
  if not next_branch then return end

  -- Queue of edit commands that we will execute when nvim is ready.
  local queue = Edit.Queue.new()

  -- If this branch has a leaf pair, we want to expand it.
  if next_branch.leaf then
    local start
    local leaf = next_branch.leaf

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
  else
    -- Reset everything if there are no more branches.
    self:reset()
  end

  -- Execute our edits and markings
  vim.schedule(function() queue:execute() end)
end

function Input:reset()
  self.current_branch = self.tree.openers
  self.current_context = nil
end

return Input
