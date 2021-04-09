local Utils = require "pears.utils"

local PearTree = {}
local Trie = {}

function Trie.new(dictionary, get_key)
  local self = setmetatable({get_key = get_key, unpack(Trie.new_branch())}, {__index = Trie})

  self.branches, self.max_len = self:make(dictionary)

  return self
end

function Trie.make_key(str)
  return 'k' .. string.byte(str)
end

function Trie.make_char(key)
  return string.char(string.sub(key, 2, -1))
end

function Trie:query(chars)
  local last = nil
  local last_branch = self.branches
  local index

  chars = chars or ""

  for i = 1, #chars do
    local char = string.sub(chars, i, i)
    local key = Trie.make_key(char)
    local item = last_branch[key]

    index = i

    if item then
      if item.leaf then
        last = item.leaf
      end

      if item.branches then
        last_branch = item.branches
      else
        break
      end
    else
      break
    end
  end

  return last, index
end

function Trie.new_branch(char, parent, is_wildcard)
  return {
    leaf = nil,
    char = char,
    wildcard = nil,
    parent = parent,
    is_wildcard = is_wildcard,
    branches = {}
  }
end

function Trie:make(dictionary)
  local branches = {}
  local max_len = 0

  for _, value in pairs(dictionary) do
    value = vim.tbl_extend("force", {}, value)

    local current_list = branches
    local current_branch
    local key_string = self.get_key(value)
    local len = 0
    local is_escaped = false
    local is_wildcard = false
    local wildcard = nil

    for char in string.gmatch(key_string, ".") do
      if char == "\\" and not is_escaped then
        is_escaped = true
      else
        local key = Trie.make_key(char)

        len = len + 1

        if char == "*" and not is_escaped then
          current_branch.wildcard = value
          wildcard = value
          wildcard.next_chars = {}
          is_wildcard = true
        else
          if not current_list[key] then
            current_list[key] = Trie.new_branch(char, current_branch, is_wildcard)
          end

          if wildcard then
            table.insert(wildcard.next_chars, char)
          end

          if len > max_len then
            max_len = len
          end

          current_branch = current_list[key]
          current_list = current_branch.branches
        end

        is_escaped = false
      end
    end

    if current_branch then
      current_branch.leaf = value
    end
  end

  return branches, max_len
end

function PearTree.new(config)
  local self = setmetatable({}, {__index = PearTree})

  self:from_config(config)

  return self
end

PearTree.make_key = Trie.make_key
PearTree.make_char = Trie.make_char

function PearTree:from_config(pair_config_map)
  self.openers = Trie.new(pair_config_map, function(item)
    return item.open
  end)
  self.reverse_openers = Trie.new(pair_config_map, function(item)
    return string.reverse(item.open)
  end)
  self.closers = Trie.new(pair_config_map, function(item)
    return item.close
  end)
  self.reverse_closers = Trie.new(pair_config_map, function(item)
    return string.reverse(item.close)
  end)

  self.max_opener_len = self.openers.max_len
  self.max_closer_len = self.closers.max_len
  print(vim.inspect(self.openers))
end

function PearTree:get_wrapping_pair_at(bufnr, position)
  local before, after = Utils.get_surrounding_chars(bufnr, position, self.reverse_openers.max_len, self.closers.max_len)
  local opener = self.reverse_openers:query(string.reverse(before))
  local closer = self.closers:query(after)

  if opener and closer and opener.key == closer.key then
    return opener, closer
  end

  return nil
end

return PearTree
