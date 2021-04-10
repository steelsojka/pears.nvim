return function(conf, opts)
  local fts = {"html", "xml"}

  conf.pair("<", {
    close = ">",
    filetypes = fts})

  conf.pair("<!--", {
    close = "-->", filetypes = fts})
end
