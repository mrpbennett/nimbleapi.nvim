local M = {}

local method_hl_map = {
  GET = "FastapiMethodGET",
  POST = "FastapiMethodPOST",
  PUT = "FastapiMethodPUT",
  PATCH = "FastapiMethodPATCH",
  DELETE = "FastapiMethodDELETE",
  OPTIONS = "FastapiMethodOPTIONS",
  HEAD = "FastapiMethodHEAD",
  TRACE = "FastapiMethodTRACE",
  WEBSOCKET = "FastapiMethodWEBSOCKET",
}

---@param opts? table
function M.pick(opts)
  local routes = require("fastapi.cache").get_all_routes()
  if #routes == 0 then
    vim.notify("fastapi.nvim: no routes found", vim.log.levels.INFO)
    return
  end

  local items = {}
  for _, route in ipairs(routes) do
    table.insert(items, {
      text = route.method .. " " .. route.path .. " → " .. (route.func or "") .. "()",
      file = route.file,
      pos = { route.line, 0 },
      route = route,
    })
  end

  Snacks.picker(vim.tbl_extend("force", {
    title = "FastAPI Routes",
    items = items,
    format = function(item, _ctx)
      local route = item.route
      local method_hl = method_hl_map[route.method] or "Normal"
      return {
        { string.format("%-9s", route.method), method_hl },
        { " " },
        { string.format("%-40s", route.path), "Normal" },
        { " " },
        { (route.func or "") .. "()", "FastapiFunc" },
      }
    end,
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        vim.api.nvim_win_set_cursor(0, item.pos)
        vim.cmd("normal! zz")
      end
    end,
  }, opts or {}))
end

return M
