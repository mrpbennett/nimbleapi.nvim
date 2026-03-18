return require("telescope").register_extension({
  setup = function(_, _)
    -- Extension-specific config can be added here
  end,
  exports = {
    routes = function(opts)
      require("nimbleapi.picker").pick(opts)
    end,
  },
})
