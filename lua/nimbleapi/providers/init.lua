local M = {}

local utils = require("nimbleapi.utils")

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

---@type table<string, RouteProvider|false>
local provider_cache = {}

---@type table<string, table[]>
local diagnostics_cache = {}

---@type string|nil
local last_context_root = nil

local ROOT_MARKERS = {
  "pom.xml",
  "build.gradle",
  "build.gradle.kts",
  "settings.gradle",
  "pyproject.toml",
  "setup.py",
  "setup.cfg",
  "requirements.txt",
  ".git",
}

---@param ctx string|table|nil
---@return string|nil
local function get_context_path(ctx)
  if type(ctx) == "string" then
    return ctx ~= "" and utils.normalize(ctx) or nil
  end

  if type(ctx) == "table" then
    if ctx.filepath and ctx.filepath ~= "" then
      return utils.normalize(ctx.filepath)
    end
    if ctx.bufnr and vim.api.nvim_buf_is_valid(ctx.bufnr) then
      local filepath = vim.api.nvim_buf_get_name(ctx.bufnr)
      if filepath ~= "" then
        return utils.normalize(filepath)
      end
    end
    if ctx.cwd and ctx.cwd ~= "" then
      return utils.normalize(ctx.cwd)
    end
  end

  local bufnr = vim.api.nvim_get_current_buf()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    if filepath ~= "" then
      return utils.normalize(filepath)
    end
  end

  return nil
end

--- Resolve the nearest project root for a buffer/file context.
---@param ctx string|table|nil
---@return string
function M.resolve_root(ctx)
  local path = get_context_path(ctx)
  local startpath = path or vim.fn.getcwd()
  return utils.find_project_root(startpath, ROOT_MARKERS)
end

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
    elseif ok and not result then
      table.insert(diagnostics, {
        provider = provider.name,
        phase = "detection",
        reason = "project markers not found in " .. root,
      })
    end

    ::continue::
  end

  return nil, diagnostics
end

--- Get the active provider (cached, keyed on resolved project root).
---@param ctx string|table|nil
---@return RouteProvider|nil
function M.get_provider(ctx)
  local root = M.resolve_root(ctx)
  last_context_root = root

  if provider_cache[root] ~= nil then
    local cached = provider_cache[root]
    return cached or nil
  end

  local config = require("nimbleapi.config").options

  -- User override: find provider by name
  if config.provider then
    for _, provider in ipairs(registry) do
      if provider.name == config.provider then
        provider_cache[root] = provider
        diagnostics_cache[root] = {}
        return provider
      end
    end
    vim.notify(
      "nimbleapi.nvim: configured provider '" .. config.provider .. "' not found. "
        .. "Available: " .. table.concat(M.registered_names(), ", "),
      vim.log.levels.WARN
    )
    provider_cache[root] = false
    diagnostics_cache[root] = {}
    return nil
  end

  -- Auto-detect from project root
  local provider, diagnostics = M.detect(root)
  provider_cache[root] = provider or false
  diagnostics_cache[root] = diagnostics
  return provider
end

--- Get the last detection diagnostics (for :NimbleAPI info).
---@param root string|nil
---@return table[]
function M.get_diagnostics(root)
  return diagnostics_cache[root or last_context_root or ""] or {}
end

--- Clear the cached provider (call on refresh or workspace change).
function M.reset()
  for _, provider in ipairs(registry) do
    if provider.reset then
      provider.reset()
    end
  end
  provider_cache = {}
  diagnostics_cache = {}
  last_context_root = nil
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
---@param ctx string|table|nil
---@return boolean
function M.handles_file(filepath, ctx)
  local next_ctx = { filepath = filepath }
  if type(ctx) == "table" then
    for key, value in pairs(ctx) do
      next_ctx[key] = value
    end
    next_ctx.filepath = filepath
  end

  local provider = M.get_provider(next_ctx)
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
---@param ctx string|table|nil
---@return string[]
function M.info(ctx)
  local root = M.resolve_root(ctx)
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
   local active = M.get_provider(ctx)
  if active then
    table.insert(lines, "Active provider: " .. active.name .. " (" .. active.language .. ")")
  else
    table.insert(lines, "Active provider: none")
    local diag = M.get_diagnostics(root)
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
