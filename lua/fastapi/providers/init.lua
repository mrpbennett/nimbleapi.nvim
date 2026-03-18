local M = {}

---@class RouteProvider
---@field name string Provider identifier (e.g., "fastapi", "springboot")
---@field language string Tree-sitter language ("python", "java", etc.)
---@field file_extensions string[] File extensions this provider handles (e.g., { "py" })
---@field test_patterns string[] Test file glob patterns
---@field path_param_pattern string Lua pattern for path parameters
---@field detect fun(root: string): boolean
---@field find_app fun(root: string): table|nil
---@field get_all_routes fun(root: string): table[]
---@field extract_routes fun(filepath: string): table[]
---@field extract_includes fun(filepath: string): table[]
---@field extract_test_calls_buf fun(bufnr: integer): table[]
---@field find_project_root fun(): string

---@type RouteProvider[]
local registry = {}

---@type RouteProvider|nil
local cached_provider = nil

--- Register a route provider.
---@param provider RouteProvider
function M.register(provider)
  -- Avoid duplicate registration
  for i, existing in ipairs(registry) do
    if existing.name == provider.name then
      registry[i] = provider
      return
    end
  end
  table.insert(registry, provider)
end

--- Detect which provider matches the current project.
---@param root string Project root directory
---@return RouteProvider|nil
function M.detect(root)
  for _, provider in ipairs(registry) do
    local ok, result = pcall(provider.detect, root)
    if ok and result then
      return provider
    end
  end
  return nil
end

--- Get the active provider (cached). Respects config.provider override.
---@return RouteProvider|nil
function M.get_provider()
  if cached_provider then
    return cached_provider
  end

  local config = require("fastapi.config").options

  -- User override: find provider by name
  if config.provider then
    for _, provider in ipairs(registry) do
      if provider.name == config.provider then
        cached_provider = provider
        return cached_provider
      end
    end
    vim.notify(
      "fastapi.nvim: configured provider '" .. config.provider .. "' not found",
      vim.log.levels.WARN
    )
    return nil
  end

  -- Auto-detect from project root
  local root = vim.fn.getcwd()
  cached_provider = M.detect(root)
  return cached_provider
end

--- Clear the cached provider (call on refresh or workspace change).
function M.reset()
  -- Call per-provider reset if available
  if cached_provider and cached_provider.reset then
    cached_provider.reset()
  end
  cached_provider = nil
end

--- Get list of all file extensions across registered providers.
---@return string[]
function M.get_all_extensions()
  local exts = {}
  local seen = {}
  for _, provider in ipairs(registry) do
    for _, ext in ipairs(provider.file_extensions) do
      if not seen[ext] then
        seen[ext] = true
        table.insert(exts, ext)
      end
    end
  end
  return exts
end

--- Check if a file extension is handled by the active provider.
---@param filepath string
---@return boolean
function M.handles_file(filepath)
  local provider = M.get_provider()
  if not provider then
    return false
  end
  local ext = filepath:match("%.([^%.]+)$")
  if not ext then
    return false
  end
  for _, pext in ipairs(provider.file_extensions) do
    if ext == pext then
      return true
    end
  end
  return false
end

return M
