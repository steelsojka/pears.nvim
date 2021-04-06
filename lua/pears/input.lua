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
    current_branch = pear_tree,
    on_match = opts.on_match or Utils.noop
  }

  return setmetatable(self, {__index = Input})
end

function Input:_on_match(leaf)
  self.on_match(leaf, context, self)
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

function Input:filter_contexts(predicate)
  local contexts = {}

  for _, context in ipairs(self.contexts) do
    local keep = predicate(context)

    if keep then
      table.insert(contexts, context)
    else
      context:destroy()
    end
  end

  self.contexts = contexts
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

function Input:_replace_active_context(leaf)
end

function Input:_make_context(leaf, start_range, end_range)
  return Context.new(self.bufnr, leaf.key, start_range, end_range)
end

function Input:input(char)
  local key = PearTree.make_key(char)
  local row, col

  -- Next branch in the tree. If it's nil then we either are entering a new sequence
  -- or just entering regular input.
  local next_branch = self.current_branch and self.current_branch.branches[key]

  -- If this is a closer, check if we are part of a context with this entry.
  if self.tree.closers[key] then
    local closer_entry = self.tree.closers[key]

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

  if not row or not col then
    row, col = unpack(api.nvim_win_get_cursor(0))
  end

  local has_branches = not vim.tbl_isempty(next_branch.branches)

  -- If this branch has a leaf pair, we want to expand it.
  if next_branch.leaf then
    local start_range
    local end_range
    local leaf = next_branch.leaf

    -- If there is a current context that we have previously expanded, we
    -- want to remove the previous leafs closer and use this leafs closer.
    -- For example HTML "<" ">" would be the current context and "<!--" "-->" would
    -- replace the previous leaf.
    if self.current_context then
      local prev_context = self.current_context

      start_range = prev_context:start_range()

      local _end_range = prev_context:end_range()

      -- Delete the previous leafs end closer range.
      queue:add(Edit.delete, {(_end_range[2] or 0) - (_end_range[4] or 0) + 1})

      self:remove_context(prev_context)
    else
      -- If we don't have a current_context then this is a new sequence,
      -- so start the range at the cursor.
      start_range = {row - 1, col, row - 1, col}
    end

    local end_range = {row - 1, col + 1, row - 1, col + #leaf.close}

    -- Insert the closer
    queue:add(Edit.insert, {leaf.close})
    -- Reset the cursor position
    queue:add(Edit.left, {#leaf.close})

    local new_context = self:_make_context(leaf, start_range, end_range)

    -- Queue the context to add extmarks... if this fails we don't want to throw an error.
    -- Instead just remove the context and move on.
    queue:add(function()
      local success = pcall(function() new_context:mark() end)

      if not success then
        print(vim.inspect(new_context))
        self:remove_context(new_context)
      end
    end)

    table.insert(self.contexts, new_context)

    -- If there are more branches after this leaf then track it for additional input.
    if has_branches then
      self.current_context = new_context
    end
  end

  if has_branches then
    self.current_branch = next_branch
  else
    -- Reset everything if there are no more branches.
    self:reset()
  end

  -- Execute our edits and markings
  vim.schedule(function() queue:execute() end)
end

function Input:reset()
  self.current_branch = self.tree
  self.current_context = nil
end

return Input
