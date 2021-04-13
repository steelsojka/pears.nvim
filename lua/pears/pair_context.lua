local PearTree = require "pears.pear_tree"
local MarkedRange = require "pears.marked_range"

local PairContext = {}

function PairContext.new(branch, range, bufnr)
  local self = {
    top_branch = branch,
    bufnr = bufnr,
    trie = nil,
    branch = branch,
    wildcard = nil,
    wildcard_start = nil,
    range = MarkedRange.new(bufnr, range),
    chars = {}
  }

  return setmetatable(self, {__index = PairContext})
end

function PairContext:is_valid_path(chars)

end

function PairContext:step_forward(char, col)
  local key = PearTree.make_key(char)

  if self.branch and self.branch.branches and self.branch.branches[key] then
    table.insert(self.chars, char)
    self.branch = self.branch.branches[key]

    if self.branch.leaf then
      self._check_wildcard(self.branch.leaf, col)

      return true, self.branch.leaf
    end

    return true
  end

  return false
end

function PairContext:step_backward(col)
  if self.branch and self.branch.parent and not self:at_start() then
    if self.wildcard == self.branch.leaf then
      self.wildcard = nil
    end

    table.remove(self.chars)
    self.branch = self.branch.parent
    self._check_wildcard(self.branch.leaf, col)
  end
end

function PairContext:at_end()
  return self.branch and vim.tbl_isempty(self.branch.branches)
end

function PairContext:at_start()
  return self.branch == self.top_branch
end

function PairContext:get_current_leaf()
  if self.branch and self.branch.leaf then
    return self.branch.leaf
  end

  if self.wildcard then
    return self.wildcard
  end

  return nil
end

function PairContext:destroy()
  self.range:unmark()
end

function PairContext:_check_wildcard(leaf, col)
  if leaf and leaf.is_wildcard then
    self.wildcard = leaf
    self.wildcard_start = col
  end
end

return PairContext
