local PearTree = {}

function PearTree.new()
  local self = {
    leaf = nil,
    branches = {},
    openers = {},
    closers = {}
  }

  return setmetatable(self, {__index = PearTree})
end

function PearTree.make_key(str)
  return 'k' .. string.byte(str)
end

function PearTree.make_char(key)
  return string.char(string.sub(key, 2, -1))
end

function PearTree:get_openers()
  return self.openers
end

function PearTree:from_config(pair_config_map)
  self.branches = {}
  self.openers = {}
  self.closers = {}

  local seen_openers = {}

  for key, config in pairs(pair_config_map) do
    local current_list = self.branches
    local current_branch

    self.closers[config.close_key] = config

    for char in string.gmatch(config.open, ".") do
      local key = PearTree.make_key(char)

      if not seen_openers[key] then
        table.insert(self.openers, char)
        seen_openers[key] = true
      end

      if not current_list[key] then
        current_list[key] = {
          leaf = nil,
          char = char,
          branches = {}
        }
      end

      current_branch = current_list[key]
      current_list = current_branch.branches
    end

    if current_branch then
      current_branch.leaf = config
    end
  end
end

return PearTree
