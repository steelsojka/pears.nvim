local PearTree = require "pears.pear_tree"
local MarkedRange = require "pears.marked_range"
local Utils = require "pears.utils"

local PairContext = {}

function PairContext.new(branch, range, bufnr)
  local self = {
    id = math.random(10000),
    top_branch = branch,
    bufnr = bufnr,
    trie = nil,
    branch = branch,
    leaf = branch.leaf,
    range = MarkedRange.new(bufnr, range),
    chars = {}
  }

  return setmetatable(self, {__index = PairContext})
end

function PairContext:step_forward(char)
  local key = PearTree.make_key(char)

  if self.branch.branches and self.branch.branches[key] then
    table.insert(self.chars, char)
    self.branch = self.branch.branches[key]
    self.leaf = self.branch.leaf or self.branch.wildcard

    return {did_step = true, done = false}
  else
    local wildcard = self:_get_nearest_wildcard()

    self.leaf = wildcard

    if wildcard then
      return {did_step = false, done = false}
    end
  end

  return {did_step = false, done = true}
end

function PairContext:step_backward()
  if self.branch and self.branch.parent and not self:at_start() then
    table.remove(self.chars)
    self.branch = self.branch.parent
    self.leaf = self.branch.leaf or self:_get_nearest_wildcard()
  end
end

function PairContext:at_end()
  return self.branch and vim.tbl_isempty(self.branch.branches)
end

function PairContext:at_start()
  return self.branch == self.top_branch
end

function PairContext:destroy()
  self.range:unmark()
end

function PairContext:_get_nearest_wildcard()
  local current = self.branch

  while current do
    if current.wildcard then
      break
    end

    current = current.parent
  end

  return (current and current.wildcard) or nil
end

return PairContext
