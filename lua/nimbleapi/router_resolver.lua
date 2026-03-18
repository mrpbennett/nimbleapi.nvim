local parser = require("nimbleapi.parser")
local import_resolver = require("nimbleapi.import_resolver")
local utils = require("nimbleapi.utils")

local M = {}

---@class RouterNode
---@field name string Router variable name
---@field prefix string URL prefix from include_router()
---@field file string Source file path
---@field routes table[] Route definitions
---@field children RouterNode[] Nested routers

---@class AppDefinition
---@field file string Entry file path
---@field var_name string App variable name
---@field routes table[] Direct routes on the app
---@field routers RouterNode[] Included routers

--- Build the full route tree starting from the app entry file.
---@param app table { file, var_name } from app_finder
---@return AppDefinition|nil
function M.build_route_tree(app)
  if not app or not app.file then
    return nil
  end

  local project_root = import_resolver.find_project_root()
  local visited = {} -- prevent infinite recursion

  local tree = {
    file = app.file,
    var_name = app.var_name or "app",
    routes = {},
    routers = {},
  }

  -- Extract direct routes defined on the app
  tree.routes = parser.extract_routes(app.file)

  -- Extract include_router() calls
  local includes = parser.extract_include_routers(app.file)
  local import_table = parser.extract_imports(app.file)

  visited[app.file] = true

  for _, inc in ipairs(includes) do
    local router_node = M._resolve_router(inc, import_table, app.file, project_root, visited)
    if router_node then
      table.insert(tree.routers, router_node)
    end
  end

  return tree
end

--- Resolve a single include_router() call into a RouterNode.
---@param inc table Include info from parser
---@param import_table table Import lookup from the including file
---@param including_file string Path of the file containing the include
---@param project_root string
---@param visited table Set of already-visited file paths
---@return RouterNode|nil
function M._resolve_router(inc, import_table, including_file, project_root, visited)
  local ref = inc.router_ref
  if not ref then
    return nil
  end

  -- Find the import entry for the router reference
  local import_info = import_resolver.resolve_router_ref(ref, import_table)
  if not import_info then
    return nil
  end

  -- Resolve the import to a file path
  local resolved_file = import_resolver.resolve_import(including_file, import_info, project_root)
  if not resolved_file then
    return nil
  end

  -- Determine the router name for display
  local display_name
  if ref.type == "attribute" then
    display_name = ref.object
  else
    display_name = ref.name
  end

  -- Prevent infinite recursion
  if visited[resolved_file] then
    return {
      name = display_name,
      prefix = inc.prefix or "",
      file = resolved_file,
      routes = {},
      children = {},
    }
  end
  visited[resolved_file] = true

  -- Extract routes from the resolved router file
  local routes = parser.extract_routes(resolved_file)

  -- Check for nested include_router() calls (routers including sub-routers)
  local sub_includes = parser.extract_include_routers(resolved_file)
  local sub_import_table = parser.extract_imports(resolved_file)
  local children = {}

  for _, sub_inc in ipairs(sub_includes) do
    local child = M._resolve_router(sub_inc, sub_import_table, resolved_file, project_root, visited)
    if child then
      table.insert(children, child)
    end
  end

  return {
    name = display_name,
    prefix = inc.prefix or "",
    file = resolved_file,
    routes = routes,
    children = children,
  }
end

--- Flatten a route tree into a list of routes with full paths.
---@param tree AppDefinition
---@return table[] flat_routes
function M.flatten_routes(tree)
  if not tree then
    return {}
  end

  local flat = {}

  -- Add direct app routes
  for _, route in ipairs(tree.routes) do
    table.insert(flat, {
      method = route.method,
      path = route.path,
      func = route.func,
      file = route.file,
      line = route.line,
      router_obj = route.router_obj,
    })
  end

  -- Recursively add router routes with prefix
  local function flatten_router(router_node, parent_prefix)
    local prefix = parent_prefix .. (router_node.prefix or "")

    for _, route in ipairs(router_node.routes) do
      local full_path = prefix .. route.path
      -- Normalize double slashes (but keep leading slash)
      full_path = full_path:gsub("//+", "/")
      table.insert(flat, {
        method = route.method,
        path = full_path,
        func = route.func,
        file = route.file,
        line = route.line,
        router_name = router_node.name,
        router_obj = route.router_obj,
      })
    end

    for _, child in ipairs(router_node.children or {}) do
      flatten_router(child, prefix)
    end
  end

  for _, router in ipairs(tree.routers) do
    flatten_router(router, "")
  end

  return flat
end

return M
