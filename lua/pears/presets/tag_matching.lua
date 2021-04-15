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
        "xml"}},
    capture_content = "^[a-zA-Z_\\-]+",
    expand_when = "[>]",
    -- Don't expand for self closing tags <input type="text" />
    should_expand = function(args)
      local before = Utils.get_surrounding_chars(args.bufnr, nil, 1)

      return before ~= "/"
    end
  })
end
