local R = require "pears.rule"

return function(conf, opts)
  -- Default to HTML void elements, which don't require a closing tag or a trailing slash (although the trailing slash is required for valid XHTML)
  local skip_tags = opts.skip_tags or {
    'area', 'base', 'br', 'col', 'command', 'embed', 'hr', 'img', 'input', 'keygen', 'link', 'meta', 'param', 'source', 'track', 'wbr'
  }

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
        "markdown",
        "eruby"}},
    capture_content = "^[a-zA-Z_\\-]+",
    expand_when = R.char "[>]",
    should_expand = R.all_of(
      -- Don't expand for self closing tags <input type="text" />
      R.not_(R.end_of_context "[/]"),
      -- Don't expand if we made a closing tag </div>
      -- Don't expand if we made have a space after the opening angle 1 < 3
      R.not_(R.start_of_context "<[/ ]"),
      -- Don't expand inside strings
      R.when(
        function() return not opts.expand_in_strings end,
        R.not_(R.child_of_node {"string"})),
      -- Don't expand when there is a preceding character "SomeClass<T> (only for tsx)"
      R.when(
        R.lang {"typescript", "tsx"},
        R.not_(R.start_of_context "[a-zA-Z0-9]")),
      -- Don't expand for tags configured to be skipped
      R.not_(
        R.any_of(
          unpack(vim.tbl_map(function (tag)
              return R.end_of_context(tag.."[^>]*")
            end,
            skip_tags
          ))
        )
      ),
      -- An additional rule that a user can add on.
      opts.should_expand or R.T)})
end
