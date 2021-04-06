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
    local fenv = setmetatable({
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

    setfenv(handler, fenv)
    handler()
  end

  return config
end

function M.get_default_config()
  return M.exec_config_handler(function()
    pair("{", "}")
    pair("[", "]")
    pair("(", ")")
    pair("\"", "\"")
    pair("'", "'")
    pair("`", "`")
    pair("<", ">")
    pair("\"\"\"", "\"\"\"")
    pair("<!--", "-->")
  end)
end

function M.make_user_config(config_handler)
  return M.exec_config_handler(config_handler, M.get_default_config())
end

return M
