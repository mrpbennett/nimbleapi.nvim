local M = {}

---@type table<string, { routes: table[], mtime: number }>
local file_cache = {}

---@type table|nil Cached route tree (AppDefinition)
local tree_cache = nil

---@type table[]|nil Cached flat route list
local flat_cache = nil

--- Invalidate cache for a specific file.
---@param filepath string
function M.invalidate(filepath)
  filepath = vim.fs.normalize(filepath)
  file_cache[filepath] = nil
  tree_cache = nil
  flat_cache = nil
end

--- Invalidate all caches.
function M.invalidate_all()
  file_cache = {}
  tree_cache = nil
  flat_cache = nil
end

--- Check if a file's cache entry is still valid by comparing mtime.
---@param filepath string
---@return boolean
local function is_valid(filepath)
  local entry = file_cache[filepath]
  if not entry then
    return false
  end

  local stat = vim.uv.fs_stat(filepath)
  if not stat then
    return false
  end

  return entry.mtime == stat.mtime.sec
end

--- Get cached routes for a single file, parsing if needed.
---@param filepath string
---@return table[]
function M.get_file_routes(filepath)
  filepath = vim.fs.normalize(filepath)

  if is_valid(filepath) then
    return file_cache[filepath].routes
  end

  local routes = require("fastapi.parser").extract_routes(filepath)
  local stat = vim.uv.fs_stat(filepath)
  file_cache[filepath] = {
    routes = routes,
    mtime = stat and stat.mtime.sec or 0,
  }

  return routes
end

--- Build and cache the full route tree.
---@return table|nil AppDefinition
function M.get_route_tree()
  if tree_cache then
    return tree_cache
  end

  local app = require("fastapi.app_finder").find_app()
  if not app then
    vim.notify("fastapi.nvim: no FastAPI app found in workspace", vim.log.levels.WARN)
    return nil
  end

  tree_cache = require("fastapi.router_resolver").build_route_tree(app)
  return tree_cache
end

--- Get all routes as a flat list (with full paths).
---@return table[]
function M.get_all_routes()
  if flat_cache then
    return flat_cache
  end

  local tree = M.get_route_tree()
  if not tree then
    return {}
  end

  flat_cache = require("fastapi.router_resolver").flatten_routes(tree)
  return flat_cache
end

--- Build a lookup table from path -> route for codelens matching.
---@return table<string, table> path_to_route
function M.get_route_lookup()
  local routes = M.get_all_routes()
  local lookup = {}

  for _, route in ipairs(routes) do
    -- Index by path for quick lookup
    local key = route.path
    if not lookup[key] then
      lookup[key] = {}
    end
    table.insert(lookup[key], route)
  end

  return lookup
end

return M
