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
    capture_content = "^[a-zA-Z_%-]+",
    should_expand = function(args)
      return args.char == ">"
    end
  })
end
