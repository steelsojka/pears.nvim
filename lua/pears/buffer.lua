local Utils = require "pears.utils"
local PearTree = require "pears.pear_tree"
local Pointer = require "pears.pointer"
local api = vim.api

local M = {}

local function is_leafs_balanced(stack_a, match, direction, match_closer)
  if stack_a and match then
    if stack_a.leaf.key == match.leaf.key then
      if match.leaf.is_mirrored then
        return true
      end

      if direction == Pointer.Direction.Forward then
        return not stack_a.closer and match_closer
      else
        return stack_a.closer and not match_closer
      end
    end
  end

  return false
end

-- Iters over pair part matches and pair matches.
-- The iterator returns the pair part match (open/closer)
-- and a complete pair match as the second return value (if it exists).
--
-- The algorithm for this is as follows.
--
-- * Read next character "function () {|}"
-- * If the next character is listed an open trie or closer trie
--   * Continue reading until we get the longest leaf value
-- * Take then longest read value from the open or close trie
-- * Set the pointer to the last read value "function() |{}"
-- * If there is a matching pair on the unbalanced stack
--   * Create a pair match and compute ranges
--   * Remove the pair part from the stack
--   * Return the part and pair
-- * Else
--   * Push the pair part onto the unbalanced stack
--   * Compute ranges
--   * Return the part and nil for the pair
--
-- @param opts.range The range of the buffer to iterate over.
-- @param opts.bufnr The buffer.
-- @param opts.open_trie The trie to use for opening pairs.
-- @param opts.close_trie The trie to use for closing pairs.
-- @param opts.direction The direction we should move over the range.
function M.iter_pairs(opts)
  local range = opts.range
  local bufnr = opts.bufnr
  local open_trie = opts.open_trie
  local close_trie = opts.close_trie
  local direction = opts.direction
  local is_forward = direction == Pointer.Direction.Forward
  local col_offset = range[2]
  local row_offset = range[1]
  local row, col

  if is_forward then
    row = 0
    col = 0
  else
    row, col = unpack(Utils.get_position_offset(range, {range[3], range[4]}))
  end

  local lines = Utils.get_content_from_range(bufnr, range)
  local pairs = {}
  local stack = {}
  local done = is_forward
    and Pointer.at_end(row, col, lines)
    or Pointer.at_start(row, col)

  return function()
    if done then return end

    local result
    local pair_result

    while not result and not pair_result do
      local open_match, open_row, open_col = Pointer.match(open_trie, row, col, lines, direction)
      local close_match, close_row, close_col = Pointer.match(close_trie, row, col, lines, direction)
      local match
      local is_close_match = false
      local start_row = row
      local start_col = col

      if open_match then
        if close_match then
          local next_row, next_col

          if is_forward then
            next_row, next_col = Pointer.max(open_row, open_col, close_row, close_col)
          else
            next_row, next_col = Pointer.min(open_row, open_col, close_row, close_col)
          end

          row = next_row
          col = next_col

          if Pointer.eq(next_row, next_col, open_row, open_col) then
            match = open_match
          else
            match = close_match
            is_close_match = true
          end
        else
          row = open_row
          col = open_col
          match = open_match
        end
      elseif close_match then
        row = close_row
        col = close_col
        match = close_match
        is_close_match = true
      end

      if match then
        if match.leaf then
          local stack_item = stack[1]

          if is_leafs_balanced(stack_item, match, direction, is_close_match) then
            local range
            local start_range
            local end_range

            if is_forward then
              range = {stack_item.start_row, stack_item.start_col, row + row_offset, col + col_offset}
              start_range = {stack_item.start_row, stack_item.start_col, stack_item.end_row, stack_item.end_col}
              end_range = {start_row + row_offset, start_col + col_offset, row + row_offset, col + col_offset}
            else
              range = {row + row_offset, col + col_offset, stack_item.end_row, stack_item.end_col}
              end_range = {stack_item.start_row, stack_item.start_col, stack_item.end_row, stack_item.end_col}
              start_range = {row + row_offset, col + col_offset, start_row + row_offset, start_col + col_offset}
            end

            pair_result = {
              leaf = match.leaf,
              range = range,
              inner_range = Utils.get_inner_range(start_range, end_range),
              start_range = start_range,
              end_range = end_range}
            result = stack_item
            table.remove(stack, 1)
          else
            result = {
              leaf = match.leaf,
              closer = is_close_match,
              start_row = (is_forward and start_row or row) + row_offset,
              start_col = (is_forward and start_col or col) + col_offset,
              end_row = (is_forward and row or start_row) + row_offset,
              end_col = (is_forward and col or start_col) + col_offset}
            table.insert(stack, 1, result)
          end
        elseif match.wildcard then
          -- TODO: currently not supported
        end
      end

      _, row, col = Pointer.move(row, col, lines, direction)

      if start_row ~= row then
        col_offset = 0
      end

      if not row or not col then
        break
      end
    end

    if row and col then
      done = is_forward
        and Pointer.at_end(row, col, lines)
        or Pointer.at_start(row, col)
    else
      done = true
    end

    return result, pair_result
  end
end

local function is_pair_member_of(match_result, pair_result, direction)
  if match_result
    and pair_result
    and match_result.leaf.key == pair_result.leaf.key
  then
    local range = direction == Pointer.Direction.Forward
      and pair_result.start_range
      or pair_result.end_range

    return range[1] == match_result.start_row
      and range[2] == match_result.start_col
      and range[3] == match_result.end_row
      and range[4] == match_result.end_col
  end

  return false
end

local function make_pair_match(open_match, close_match)
  local start_range = {open_match.start_row, open_match.start_col, open_match.end_row, open_match.end_col}
  local end_range = {close_match.start_row, close_match.start_col, close_match.end_row, close_match.end_col}

  return {
    leaf = open_match.leaf,
    range = {open_match.start_row, open_match.start_col, close_match.end_row, close_match.end_col},
    inner_range = Utils.get_inner_range(start_range, end_range),
    start_range = start_range,
    end_range = end_range
  }
end

function M.get_containing_pair(opts)
  local tree = opts.tree
  local bufnr = opts.bufnr or api.nvim_win_get_buf(0)
  local position = opts.position or Utils.get_cursor()
  local before_range, after_range = Utils.get_wrapping_ranges(bufnr, position[1], position[2], opts.range)
  local open_iter = M.iter_pairs {
    bufnr = bufnr,
    range = before_range,
    direction = Pointer.Direction.Backwards,
    open_trie = tree.reverse_openers,
    close_trie = tree.reverse_closers
  }
  local close_iter = M.iter_pairs {
    bufnr = bufnr,
    range = after_range,
    direction = Pointer.Direction.Forward,
    open_trie = tree.openers,
    close_trie = tree.closers
  }

  local open_match = nil
  local open_stack = {}
  local before_match, before_pair = open_iter()

  while not open_match and before_match do
    -- If we closed the pair then remove it from a possible open.
    if is_pair_member_of(open_stack[1], before_pair, Pointer.Direction.Backwards) then
      table.remove(open_stack, 1)
    end

    if before_match and not before_pair then
      if before_match.leaf.is_mirrored then
        table.insert(open_stack, 1, before_match)
      elseif not before_match.closer then
        open_match = before_match
      end
    end

    before_match, before_pair = open_iter()
  end

  if open_stack[1] then
    open_match = open_stack[1]
  end

  if not open_match then return end

  local close_stack = {}

  for after_match, after_pair in close_iter do
    -- If we closed the pair then remove it from a possible open.
    if is_pair_member_of(close_stack[1], after_pair, Pointer.Direction.Forward) then
      table.remove(close_stack, 1)
    end

    if after_match.leaf.is_mirrored then
      if open_match.leaf.key == after_match.leaf.key then
        return make_pair_match(open_match, after_match)
      else
        table.insert(close_stack, 1, after_match)
      end
    elseif after_match.closer and not after_pair then
      if after_match.leaf.key == open_match.leaf.key then
        return make_pair_match(open_match, after_match)
      else
        return
      end
    end
  end

  return nil
end

return M
