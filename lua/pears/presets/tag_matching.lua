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
    expand_when = "[>]"
  })
end
