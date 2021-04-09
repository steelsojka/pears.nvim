local Utils = require "pears.utils"
local Edit = require "pears.edit"

local M = {}

function M.get_escaped_key(key)
  return "k" .. string.gsub(key, ".", string.byte)
end

function M.pair_to_table(value)
  return type(value) == "table" and value or {close = value}
end

function M.normalize_pair(key, value)
  local entry = M.pair_to_table(value)

  entry.key = M.get_escaped_key(key)
  entry.handle_return = entry.handle_return or Edit.return_and_indent
  entry.open = entry.open or key
  entry.close = entry.close or ""
  entry.should_expand = entry.should_expand or function() return true end
  entry.close_key = M.get_escaped_key(entry.close)

  return entry
end

function M.should_include(value, arg)
  if Utils.is_table(arg) then
    -- inclusion and exclusion tables
    -- { includes = {'ruby'}, excludes = {'kotlin'} }
    if vim.tbl_islist(arg.include) or vim.tbl_islist(arg.exclude) then
      if vim.tbl_islist(arg.exclude) and vim.tbl_contains(arg.exclude, value) then
        return false
      end

      if vim.tbl_islist(arg.include) and not vim.tbl_contains(arg.include, value) then
        return false
      end
    end

    -- Value is a list
    if vim.tbl_islist(arg) and not vim.tbl_contains(arg, value) then
      return false
    end
  end

  if Utils.is_func(arg) then
    return arg(value)
  end

  return nil
end

function M.exec_config_handler(handler, config)
  config = config or {
    pairs = {}
  }

  if handler then
    local conf = setmetatable({
      pair = function(key, value, overwrite)
        local k_key = M.get_escaped_key(key)

        if not value then
          config.pairs[k_key] = nil
        else
          local norm_value = M.pair_to_table(value)

          if overwrite then
            config.pairs[k_key] = M.normalize_pair(key, norm_value)
          else
            config.pairs[k_key] = M.normalize_pair(key, vim.tbl_extend("force", config.pairs[k_key] or {}, norm_value))
          end
        end
      end
    }, {
      __index = function(tbl, prop)
        rawset(tbl, prop, function(value)
          config[prop] = value
        end)

        return rawget(tbl, prop)
      end
    })

    handler(conf)
  end

  return config
end

function M.get_default_config()
  return M.exec_config_handler(function(c)
    c.pair("{", "}")
    c.pair("[", "]")
    c.pair("(", ")")
    c.pair("\"", "\"")
    c.pair("'", {
      close = "'",
      should_expand = Utils.negate(Utils.has_leading_alpha)
    })
    c.pair("`", "`")
    c.pair("<", ">")
    c.pair("\"\"\"", "\"\"\"")
    c.pair("<!--", "-->")
    c.pair("```", "```")
    c.pair("<?", "?>")

    c.remove_pair_on_outer_backspace(true)
    c.remove_pair_on_inner_backspace(true)
    c.expand_on_enter(true)
  end)
end

function M.make_user_config(config_handler)
  return M.exec_config_handler(config_handler, M.get_default_config())
end

return M
