local Utils = require "pears.utils"

return function(conf, opts)
  conf.pair("<*>", {
    close = "</*>",
    filetypes = opts.filetypes or {
      include = {
        "javascript",
        "typescript",
        "javascriptreact",
        "typescriptreact",
        "php",
        "jsx",
        "tsx",
        "html",
        "xml",
        "markdown"}},
    capture_content = "^[a-zA-Z_\\-]+",
    expand_when = "[>]",
    should_expand = function(args)
      local end_row, end_col = unpack(args.context.range:end_())
      -- Don't include the closing ">"
      local before = Utils.get_surrounding_chars(args.bufnr, {end_row, end_col - 1}, 1)
      local _, opening_chars = Utils.get_surrounding_chars(args.bufnr, args.context.range:start(), 2)

      -- Don't expand for self closing tags <input type="text" />
      -- Don't expand if we made a closing tag </div>
      -- Don't expand if we made have a space after the opening angle 1 < 3
      local should_expand = before ~= "/" and not string.match(opening_chars, "<[/ ]")

      -- Don't expand when there is a preceding character "SomeClass<T> (only for tsx)"
      if should_expand and string.match(args.lang, "(typescript|tsx)") then
        local before_context = Utils.get_surrounding_chars(args.bufnr, args.context.range:start())

        should_expand = not string.match(before_context, "[a-zA-Z0-9]")
      end

      return should_expand
    end})
end

