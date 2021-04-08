local Utils = require "pears.utils"
local Edit = require "pears.edit"

local M = {}

function M.get_escaped_key(key)
  return "k" .. string.gsub(key, ".", string.byte)
end

function M.normalize_pair(key, value)
  local entry = value

  if type(entry) == "string" then
    entry = { close = entry }
  end

  entry.key = M.get_escaped_key(key)
  entry.padding = entry.padding or 0
  entry.handle_return = entry.handle_return or Edit.return_and_indent
  entry.open = entry.open or key
  entry.close = entry.close or ""
  entry.should_expand = entry.should_expand or function() return true end
  entry.close_key = M.get_escaped_key(entry.close)

  return entry
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
          local norm_value = M.normalize_pair(key, value)

          if overwrite then
            config.pairs[k_key] = norm_value
          else
            config.pairs[k_key] = vim.tbl_extend("force", config.pairs[k_key] or {}, norm_value)
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
