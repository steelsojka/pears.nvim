local Utils = require "pears.utils"
local Edit = require "pears.edit"
local R = require "pears.rule"
local Parser = require "pears.parser"

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
  entry.opener = Parser.parse(entry.open or key)
  entry.closer = Parser.parse(entry.close or "")

  do
    local first_close_char = string.sub(entry.closer.chars, 1, 1)
    entry.close_key = first_close_char and M.get_escaped_key(first_close_char) or nil
  end

  entry.should_include = M.make_lang_inclusion_fn(entry.filetypes)
  entry.should_expand = entry.should_expand or R.T
  entry.should_return = entry.should_return or R.T
  entry.expand_when = entry.expand_when or R.T
  entry.should_move_right = entry.should_move_right or R.match_closer()
  entry.is_wildcard = entry.opener.is_wildcard

  return entry
end

function M.make_lang_inclusion_fn(include_arg)
  local excluded = {}
  local included = {}
  -- We want to do as much work as configuration time as possible since the
  -- resuling function will be called frequently on insert enter.

  if Utils.is_table(include_arg) then
    if vim.tbl_islist(include_arg.include) or vim.tbl_islist(include_arg.exclude) then
      if vim.tbl_islist(include_arg.include) then
        for _, lang in ipairs(include_arg.include) do
          included[lang] = true
        end
      end

      if vim.tbl_islist(include_arg.exclude) then
        for _, lang in ipairs(include_arg.exclude) do
          excluded[lang] = true
        end
      end
    elseif vim.tbl_islist(include_arg) then
      for _, lang in ipairs(include_arg) do
        included[lang] = true
      end
    end
  end

  local has_excludes = not vim.tbl_isempty(excluded)
  local has_includes = not vim.tbl_isempty(included)

  if has_excludes then
    if has_includes then
      return function(lang)
        return excluded[lang] ~= true and included[lang] == true
      end
    end

    return function(lang)
      return excluded[lang] ~= true
    end
  elseif has_includes then
    return function(lang)
      return included[lang] == true
    end
  end

  return function() return true end
end

function M.resolve_matcher_event(fn_or_string, args, default_value)
  if Utils.is_func(fn_or_string) then
    return fn_or_string(args)
  end

  if Utils.is_string(fn_or_string) and Utils.is_string(args.char) then
    return string.match(args.char, fn_or_string)
  end

  return default_value
end

function M.resolve_capture(fn_or_string, arg, ...)
  if Utils.is_func(fn_or_string) then
    return fn_or_string(arg, select(1, ...))
  end

  if Utils.is_string(fn_or_string) and Utils.is_string(arg) then
    local start, end_ = string.find(arg, fn_or_string)

    if start and end_ then
      return string.sub(arg, start, end_)
    end

    return ""
  end

  return ""
end

function M.exec_config_handler(handler, config)
  config = config or {
    preset_paths = {"pears.presets"},
    pairs = {}
  }

  if handler then
    local conf

    conf = setmetatable({
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
      end,
      preset = function(name, opts)
        local error

        for _, path in ipairs(config.preset_paths) do
          local success, preset = pcall(require, path.. "." ..name)

          if success then
            preset(conf, opts or {})
            break
          else
            error = preset
          end
        end

        if error then
          vim.api.nvim_err_writeln("pears -> " .. error)
        end
      end,
      add_preset_path = function(path)
        table.insert(config, 1, path)
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
    -- These are global configured pairs
    -- These can be disabled with `c.pair("{", nil)`
    c.pair("{", "}")
    c.pair("[", "]")
    c.pair("(", ")")
    c.pair("\"", "\"")
    c.pair("\"\"\"", "\"\"\"")
    c.pair("'''", "'''")
    c.pair("<!--", "-->")
    c.pair("'", {
      close = "'",
      should_expand = R.not_(R.start_of_context "[a-zA-Z]")
    })
    c.pair("`", "`")
    c.pair("```", "```")

    c.remove_pair_on_outer_backspace(true)
    c.remove_pair_on_inner_backspace(true)
    c.expand_on_enter(true)
  end)
end

function M.make_user_config(config_handler)
  return M.exec_config_handler(config_handler, M.get_default_config())
end

return M
