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
    expansions = {},
    chars = {}
  }

  return setmetatable(self, {__index = PairContext})
end

function PairContext:get_text()
  return self.range:is_marked() and Utils.get_content_from_range(self.bufnr, self.range:range()) or nil
end

function PairContext:_check_previous_chars(char)
  local range_text = self:get_text()

  if range_text then
    range_text = table.concat(range_text, "\n")

    for i, last_char in ipairs(self.chars) do
      local char_index = #range_text - i + 1
      local actual_char = string.sub(range_text, char_index, char_index)

      if actual_char ~= last_char then
        return false
      end
    end
  end

  return true
end

function PairContext:step_forward(char)
  local key = PearTree.make_key(char)

  if self.branch.branches and self.branch.branches[key] and self:_check_previous_chars(char) then
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

function PairContext:tag_expansion()
  if self.leaf then
    table.insert(self.expansions, self.leaf)
  end
end

function PairContext:get_last_expansion()
  return self.expansions[#self.expansions]
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
