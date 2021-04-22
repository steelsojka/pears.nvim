local Utils = require "pears.utils"

local M = {}

function M.parse(str)
  local current
  local root
  local wildcard_node
  local is_escaped = false
  local has_wildcard = false
  local prev_chars = ""
  local wildcard_opener = nil
  local wildcard_closer = nil

  for char in string.gmatch(str, ".") do
    if char == "\\" and not is_escaped then
      is_escaped = true
    else
      local node = {
        is_wildcard = false,
        char = char,
        child = nil,
        parent = current
      }

      if char == "*" and not is_escaped then
        node.is_wildcard = true
        node.wildcard_opener = prev_chars
        node.wildcard_closer = ""
        has_wildcard = true
        wildcard_node = node
      elseif wildcard_node then
        wildcard_node.wildcard_closer = wildcard_node.wildcard_closer .. char
      end

      is_escaped = false

      if current then
        current.child = node
      else
        root = node
      end

      prev_chars = prev_chars .. char
      current = node
    end
  end

  return {
    source = str,
    wildcard_opener = wildcard_opener,
    wildcard_closer = wildcard_closer,
    chars = Utils.strip_escapes(str),
    is_wildcard = has_wildcard,
    ast = root
  }
end

function M.walk_down(ast)
  local current = ast

  return function()
    if current then
      local result = current

      current = current.child

      return result
    end

    return nil
  end
end

function M.walk_up(ast)
  local current = ast

  return function()
    if current then
      local result = current

      current = current.parent

      return result
    end

    return nil
  end
end

function M.get_tail(ast)
  local result

  for item in M.walk_down(ast) do
    result = item
  end

  return result
end

return M
