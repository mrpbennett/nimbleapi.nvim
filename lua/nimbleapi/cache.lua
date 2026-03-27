local M = {}

---@type table<string, { routes: table[], mtime: number }>
local file_cache = {}

---@type table<string, table|false>
local tree_cache = {}

---@type table<string, table[]|false>
local flat_cache = {}

--- Invalidate cache for a specific file.
---@param filepath string
function M.invalidate(filepath)
  filepath = vim.fs.normalize(filepath)
  file_cache[filepath] = nil
  tree_cache = {}
  flat_cache = {}
end

--- Invalidate all caches.
function M.invalidate_all()
  file_cache = {}
  tree_cache = {}
  flat_cache = {}
  require("nimbleapi.providers").reset()
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

  local providers = require("nimbleapi.providers")
  local provider = providers.get_provider({ filepath = filepath })
  local routes
  if provider then
    routes = provider.extract_routes(filepath)
  else
    -- Fallback to direct parser call for backward compat
    routes = require("nimbleapi.parser").extract_routes(filepath)
  end

  local stat = vim.uv.fs_stat(filepath)
  file_cache[filepath] = {
    routes = routes,
    mtime = stat and stat.mtime.sec or 0,
  }

  return routes
end

--- Format a user-facing error when no provider is detected.
---@param providers_mod table The providers module
---@param root string|nil
---@return string
local function format_no_provider_message(providers_mod, root)
  local diag = providers_mod.get_diagnostics(root)
  local parts = { "nimbleapi.nvim: no supported framework detected in " .. (root or vim.fn.getcwd()) }

  -- Check if any provider had prerequisite failures — those are actionable
  for _, d in ipairs(diag) do
    if d.phase == "prerequisites" then
      table.insert(parts, d.provider .. ": " .. d.reason)
    end
  end

  if #parts == 1 then
    table.insert(parts, "Run :NimbleAPI info for details")
  end

  return table.concat(parts, "\n")
end

--- Build and cache the full route tree.
---@param ctx string|table|nil
---@return table|nil AppDefinition
function M.get_route_tree(ctx)
  local providers = require("nimbleapi.providers")
  local root = providers.resolve_root(ctx)
  if tree_cache[root] ~= nil then
    return tree_cache[root] or nil
  end

  local provider = providers.get_provider(ctx)

  if not provider then
    vim.notify(format_no_provider_message(providers, root), vim.log.levels.WARN)
    return nil
  end

  if not provider.get_route_tree then
    vim.notify(
      "nimbleapi.nvim: provider '" .. provider.name .. "' does not support route tree building",
      vim.log.levels.ERROR
    )
    return nil
  end

  local project_root = provider.find_project_root(root)
  local tree = provider.get_route_tree(project_root)
  tree_cache[root] = tree or false
  if not tree then
    vim.notify(
      "nimbleapi.nvim: no app found in workspace (provider: " .. provider.name .. ")",
      vim.log.levels.WARN
    )
  end
  return tree
end

--- Get all routes as a flat list (with full paths).
---@param ctx string|table|nil
---@return table[]
function M.get_all_routes(ctx)
  local providers = require("nimbleapi.providers")
  local root = providers.resolve_root(ctx)
  if flat_cache[root] ~= nil then
    return flat_cache[root] or {}
  end

  local active_list = providers.get_active_list(ctx)

  if not active_list or #active_list == 0 then
    -- Trigger get_route_tree so the user sees the diagnostic message
    M.get_route_tree(ctx)
    return {}
  end

  local all_routes = {}
  for _, provider in ipairs(active_list) do
    local project_root = provider.find_project_root(root)
    local routes = provider.get_all_routes(project_root)
    if routes and #routes > 0 then
      vim.list_extend(all_routes, routes)
    else
      -- Try via route tree for providers that build trees
      if provider.get_route_tree then
        local tree = provider.get_route_tree(project_root)
        if tree then
          local tree_routes = require("nimbleapi.router_resolver").flatten_routes(tree)
          if tree_routes then
            vim.list_extend(all_routes, tree_routes)
          end
        end
      end
    end
  end

  flat_cache[root] = #all_routes > 0 and all_routes or false
  return all_routes
end

--- Build a lookup table from path -> route for codelens matching.
---@param ctx string|table|nil
---@return table<string, table> path_to_route
function M.get_route_lookup(ctx)
  local routes = M.get_all_routes(ctx)
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
