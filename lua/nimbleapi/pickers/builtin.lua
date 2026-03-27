local M = {}

---@param opts? table
function M.picker(opts)
  _ = opts -- unused, accepted for API consistency
  local routes = require("nimbleapi.cache").get_all_routes()
  if #routes == 0 then
    vim.notify("nimbleapi.nvim: no routes found", vim.log.levels.INFO)
    return
  end

  local labels = {}
  for _, route in ipairs(routes) do
    table.insert(
      labels,
      string.format("%-9s %-40s → %-30s %s", route.method, route.path, (route.func or "") .. "()", vim.fn.fnamemodify(route.file, ":t"))
    )
  end

  vim.ui.select(labels, { prompt = "NimbleAPI Routes" }, function(_, idx)
    if not idx then
      return
    end
    local route = routes[idx]
    vim.cmd("edit " .. vim.fn.fnameescape(route.file))
    vim.api.nvim_win_set_cursor(0, { route.line, 0 })
    vim.cmd("normal! zz")
  end)
end

return M
