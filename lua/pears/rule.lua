local Utils = require "pears.utils"

local Rule = {}

Rule.SKIP = "__SKIP__"

local function pattern_to_list(pattern, at_start, args)
  local resolved_pattern

  if Utils.is_func(pattern) then
    resolved_pattern = pattern(args)
  else
    resolved_pattern = pattern
  end

  if Utils.is_string(resolved_pattern) then
    resolved_pattern = {resolved_pattern}
  end

  local patterns = {}

  for _, pat in ipairs(resolved_pattern) do
    table.insert(patterns, at_start and ("^" .. pat) or (pat .. "$"))
  end

  return patterns
end

local function make_check(opts)
  return function(pattern)
    local is_dynamic_pattern = Utils.is_func(pattern)

    if not is_dynamic_pattern then
      pattern = pattern_to_list(pattern, opts.at_start)
    end

    return function(args)
      local resolved_pattern = is_dynamic_pattern
        and pattern_to_list(pattern, opts.at_start, args)
        or pattern

      local before, after = Utils.split_line_at(args.bufnr, opts.get_pos(args))
      local text = opts.text_before and before or after
      local result = false

      if text then
        result = Utils.match(text, resolved_pattern)
      end

      return result
    end
  end
end

Rule.end_of_context = make_check {
  text_before = true,
  get_pos = function(args)
    return Utils.shift_pos_back(args.context.range:end_(), 1)
  end
}

Rule.start_of_context = make_check {
  at_start = true,
  get_pos = function(args)
    return Utils.shift_pos_back(args.context.range:start(), 1)
  end
}

Rule.match_next = make_check {
  at_start = true,
  get_pos = function(args) return args.cursor end
}

Rule.match_prev = make_check {
  get_pos = function(args) return args.cursor end
}

Rule.match_closer = function()
  return Rule.match_next(function(args)
    return Utils.escape_pattern(args.leaf.closer.chars)
  end)
end

function Rule.all_of(...)
  local rules = {...}

  return function(args)
    for _, rule in ipairs(rules) do
      if not rule(args) then
        return false
      end
    end

    return true
  end
end

function Rule.any_of(...)
  local rules = {...}

  return function(args)
    for _, rule in ipairs(rules) do
      if rule(args) then
        return true
      end
    end

    return false
  end
end

function Rule.cond(...)
  local conditions = {...}

  return function(args)
    for _, pair_ in ipairs(conditions) do
      if pair_[1](args) then
        return pair_[2](args)
      end
    end

    return Rule.SKIP
  end
end

function Rule.lang(pattern)
  return function(args)
    return Utils.match(args.lang, pattern)
  end
end

function Rule.when(rule, other_rule)
  return function(args)
    if rule(args) then
      return other_rule(args)
    end

    return Rule.SKIP
  end
end

function Rule.not_(rule)
  return function(args)
    local result = rule(args)

    if result ~= Rule.SKIP then
      return not result
    end

    return Rule.SKIP
  end
end

function Rule.char(pattern_or_nil)
  return function(args)
    if pattern_or_nil then
      return args.char and Utils.match(args.char, pattern_or_nil)
    end

    return args.char == nil
  end
end

function Rule.has_ts(check_utils)
  return function(args)
    if check_utils then
      local success = pcall(require, "nvim-treesitter.ts_utils")

      if not success then return false end
    end

    return args.input.ts_parser
  end
end

function Rule.child_of_node(pattern_or_list, deep)
  return Rule.when(
    Rule.has_ts(true),
    function(args)
      local ts_utils = require "nvim-treesitter.ts_utils"
      local parser = args.input.ts_parser
      local row, col = unpack(args.cursor)
      local root = ts_utils.get_root_for_position(row, col, parser)

      if root then
        local node = root:named_descendant_for_range(row, col, row, col)

        if not node then return false end

        if deep then
          local current = node

          while current do
            if Utils.match(current:type(), pattern_or_list) then
              return true
            end
            current = current:parent()
          end
        else
          return Utils.match(node:type(), pattern_or_list)
        end
      end

      return false
    end)
end

function Rule.pass(result)
  return result == Rule.SKIP or result
end

function Rule.T()
  return true
end

function Rule.F()
  return false
end

return Rule
