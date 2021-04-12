local PairContext = {}

function PairContext.new(branch)
  local self = {
    top_branch = branch,
    branch = branch,
    wildcard = nil,
    wildcard_start = nil
  }

  return setmetatable(self, {__index = PairContext})
end

function PairContext:step_forward(key, col)
  if self.branch and self.branch[key] then
    self.branch = self.branch[key].branches

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

  return true
end

function PairContext:_check_wildcard(leaf, col)
  if leaf and leaf.is_wildcard then
    self.wildcard = leaf
    self.wildcard_start = col
  end
end

return PairContext
