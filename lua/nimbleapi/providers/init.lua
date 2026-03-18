local M = {}

---@class RouteProvider
---@field name string Provider identifier (e.g., "fastapi", "spring")
---@field language string Tree-sitter language ("python", "java", etc.)
---@field file_extensions string[] File extensions this provider handles (e.g., { "py" })
---@field test_patterns string[] Test file glob patterns
---@field path_param_pattern string Lua pattern for path parameters
---@field detect fun(root: string): boolean
---@field check_prerequisites fun(): { ok: boolean, message: string|nil }
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

---@type string|nil
local cached_root = nil

---@type table[]|nil Last detection diagnostics
local last_diagnostics = nil

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

--- Get names of all registered providers (for debugging).
---@return string[]
function M.registered_names()
  return vim.tbl_map(function(p) return p.name end, registry)
end

--- Detect which provider matches the current project, collecting diagnostics.
---@param root string
---@return RouteProvider|nil provider
---@return table[] diagnostics
function M.detect(root)
  local diagnostics = {}

  for _, provider in ipairs(registry) do
    -- Check prerequisites first (TS parser installed, etc.)
    if provider.check_prerequisites then
      local prereq = provider.check_prerequisites()
      if not prereq.ok then
        table.insert(diagnostics, {
          provider = provider.name,
          phase = "prerequisites",
          reason = prereq.message or "prerequisites not met",
        })
        goto continue
      end
    end

    -- Check if this project matches the provider
    local ok, result = pcall(provider.detect, root)
    if ok and result then
      return provider, diagnostics
    elseif not ok then
      table.insert(diagnostics, {
        provider = provider.name,
        phase = "detection",
        reason = "detect() error: " .. tostring(result),
      })
    end

    ::continue::
  end

  return nil, diagnostics
end

--- Get the active provider (cached, keyed on cwd). Respects config.provider override.
---@return RouteProvider|nil
function M.get_provider()
  local root = vim.fn.getcwd()

  -- Return cached provider if cwd hasn't changed
  if cached_provider and cached_root == root then
    return cached_provider
  end

  local config = require("nimbleapi.config").options

  -- User override: find provider by name
  if config.provider then
    for _, provider in ipairs(registry) do
      if provider.name == config.provider then
        cached_provider = provider
        cached_root = root
        last_diagnostics = nil
        return cached_provider
      end
    end
    vim.notify(
      "nimbleapi.nvim: configured provider '" .. config.provider .. "' not found. "
        .. "Available: " .. table.concat(M.registered_names(), ", "),
      vim.log.levels.WARN
    )
    return nil
  end

  -- Auto-detect from project root
  local provider, diagnostics = M.detect(root)
  cached_provider = provider
  cached_root = root
  last_diagnostics = diagnostics
  return cached_provider
end

--- Get the last detection diagnostics (for :NimbleAPI info).
---@return table[]
function M.get_diagnostics()
  return last_diagnostics or {}
end

--- Clear the cached provider (call on refresh or workspace change).
function M.reset()
  -- Call per-provider reset if available
  if cached_provider and cached_provider.reset then
    cached_provider.reset()
  end
  cached_provider = nil
  cached_root = nil
  last_diagnostics = nil
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

--- Build a diagnostic report for :NimbleAPI info.
---@return string[]
function M.info()
  local root = vim.fn.getcwd()
  local lines = {}

  table.insert(lines, "nimbleapi.nvim — Provider Info")
  table.insert(lines, string.rep("─", 40))
  table.insert(lines, "Project root: " .. root)
  table.insert(lines, "")

  -- Registered providers
  table.insert(lines, "Registered providers:")
  for _, provider in ipairs(registry) do
    local prereq_status = "ok"
    if provider.check_prerequisites then
      local prereq = provider.check_prerequisites()
      if not prereq.ok then
        prereq_status = prereq.message or "failed"
      end
    end
    local detected = false
    if prereq_status == "ok" then
      local ok, result = pcall(provider.detect, root)
      detected = ok and result
    end
    table.insert(lines, string.format(
      "  %s [%s] — prereqs: %s, detected: %s",
      provider.name,
      provider.language,
      prereq_status,
      detected and "yes" or "no"
    ))
  end

  table.insert(lines, "")

  -- Active provider
  local active = M.get_provider()
  if active then
    table.insert(lines, "Active provider: " .. active.name .. " (" .. active.language .. ")")
  else
    table.insert(lines, "Active provider: none")
    local diag = M.get_diagnostics()
    if #diag > 0 then
      table.insert(lines, "")
      table.insert(lines, "Detection diagnostics:")
      for _, d in ipairs(diag) do
        table.insert(lines, string.format("  %s [%s]: %s", d.provider, d.phase, d.reason))
      end
    end
  end

  return lines
end

return M
