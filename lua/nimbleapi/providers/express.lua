local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")

-- ---------------------------------------------------------------------------
-- HTTP method lookup tables
-- ---------------------------------------------------------------------------

local EXPRESS_METHODS = {
  get     = "GET",
  post    = "POST",
  put     = "PUT",
  delete  = "DELETE",
  patch   = "PATCH",
  options = "OPTIONS",
  head    = "HEAD",
  all     = "ANY",
}

local HTTP_METHODS_SET = { get = true, post = true, put = true, delete = true, patch = true, options = true, head = true }

-- ---------------------------------------------------------------------------
-- Path normalization
-- ---------------------------------------------------------------------------

--- Normalize Express path parameters to {param} style.
--- :param -> {param}, *wildcard -> {wildcard}
---@param path string
---@return string
local function normalize_path(path)
  path = path:gsub(":([%w_]+)", "{%1}")
  path = path:gsub("%*([%w_]+)", "{%1}")
  return path
end

-- ---------------------------------------------------------------------------
-- Two-pass extraction helpers
-- ---------------------------------------------------------------------------

--- Extract direct app.METHOD('/path', handler) routes via tree-sitter query.
---@param root_node userdata TSNode
---@param source string File content
---@param filepath string Absolute file path
---@param language string "javascript" or "typescript"
---@return table[] routes
local function extract_direct_routes(root_node, source, filepath, language)
  local ok, query = pcall(parser.get_query_public, "express-routes", language)
  if not ok or not query then return {} end

  local routes = {}
  for _, match, _ in query:iter_matches(root_node, source, 0, -1) do
    local method_text, path_text, func_text, line
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "http_method" then
        method_text = parser.get_text(node, source)
      elseif name == "route_path" then
        path_text = parser.get_text(node, source)
      elseif name == "func_name" then
        local nt = node:type()
        if nt == "identifier" or nt == "member_expression" then
          func_text = parser.get_text(node, source)
        else
          func_text = ""
        end
      elseif name == "route_def" then
        line = node:range() + 1
      end
    end
    local method = EXPRESS_METHODS[method_text]
    if method and path_text then
      table.insert(routes, {
        method = method,
        path   = normalize_path(path_text),
        func   = func_text or "",
        file   = filepath,
        line   = line or 0,
      })
    end
  end
  return routes
end

--- Walk a call_expression chain to extract app.route('/path').METHOD(h)... patterns.
--- Returns { route_path=string, methods={{method,handler,line}...} } or nil.
---@param node userdata TSNode
---@param source string
---@return table|nil
local function walk_chain(node, source)
  if node:type() ~= "call_expression" then return nil end

  local func_node, args_node
  for i = 0, node:child_count() - 1 do
    local c = node:child(i)
    if c:type() == "member_expression" then func_node = c
    elseif c:type() == "arguments" then args_node = c
    end
  end
  if not func_node or not args_node then return nil end

  local prop
  for i = 0, func_node:child_count() - 1 do
    local c = func_node:child(i)
    if c:type() == "property_identifier" then prop = c; break end
  end
  if not prop then return nil end

  local method_text = parser.get_text(prop, source)
  local obj = func_node:child(0)

  -- Base case: .route('/path') call
  if method_text == "route" then
    local path = nil
    for i = 0, args_node:child_count() - 1 do
      local arg = args_node:child(i)
      if arg:type() == "string" then
        for j = 0, arg:child_count() - 1 do
          local sn = arg:child(j)
          if sn:type() == "string_fragment" then
            path = parser.get_text(sn, source)
            break
          end
        end
        break
      end
    end
    return path and { route_path = path, methods = {} } or nil
  end

  -- Recursive case: HTTP method wrapping a deeper chain
  if HTTP_METHODS_SET[method_text] and obj then
    local chain = walk_chain(obj, source)
    if chain then
      local handler_node = nil
      for i = 0, args_node:child_count() - 1 do
        local arg = args_node:child(i)
        if arg:named() then handler_node = arg; break end
      end
      local handler = ""
      if handler_node then
        local nt = handler_node:type()
        if nt == "identifier" or nt == "member_expression" then
          handler = parser.get_text(handler_node, source)
        end
      end
      local row = node:range()
      table.insert(chain.methods, {
        method  = EXPRESS_METHODS[method_text] or method_text:upper(),
        handler = handler,
        line    = row + 1,
      })
      return chain
    end
  end

  return nil
end

--- Extract app.route('/path').get(h).post(h) chain routes by walking top-level statements.
--- Only scans direct children of root to avoid duplicate matches from intermediate chain nodes.
---@param root_node userdata TSNode
---@param source string
---@param filepath string
---@return table[] routes
local function extract_chain_routes(root_node, source, filepath)
  local routes = {}
  for i = 0, root_node:child_count() - 1 do
    local stmt = root_node:child(i)
    if stmt:type() == "expression_statement" then
      local call = stmt:child(0)
      if call and call:type() == "call_expression" then
        local result = walk_chain(call, source)
        if result and #result.methods > 0 then
          for _, m in ipairs(result.methods) do
            table.insert(routes, {
              method = m.method,
              path   = normalize_path(result.route_path),
              func   = m.handler,
              file   = filepath,
              line   = m.line,
            })
          end
        end
      end
    end
  end
  return routes
end

--- Extract all routes from a single Express file using two-pass extraction.
--- Pass 1: Tree-sitter query for direct app.METHOD('/path', handler) calls.
--- Pass 2: Lua AST walker for app.route('/path').get(h).post(h) chains.
---@param filepath string Absolute path to .js or .ts file
---@param language string "javascript" or "typescript"
---@return table[] routes
local function extract_routes(filepath, language)
  local root_node, source = parser.parse_file(filepath, language)
  if not root_node or not source then return {} end

  local direct = extract_direct_routes(root_node, source, filepath, language)
  local chained = extract_chain_routes(root_node, source, filepath)

  local all = {}
  for _, r in ipairs(direct) do table.insert(all, r) end
  for _, r in ipairs(chained) do table.insert(all, r) end
  table.sort(all, function(a, b) return a.line < b.line end)
  return all
end

--- Get all routes across project files for a given set of extensions.
---@param root string Project root directory
---@param extensions string[] File extensions to scan (e.g., {"js"} or {"ts"})
---@param language string "javascript" or "typescript"
---@return table[] routes
local function get_all_routes_for_ext(root, extensions, language)
  local all_routes = {}
  for _, ext in ipairs(extensions) do
    local files = utils.glob_files(root, "**/*." .. ext, {
      "node_modules", ".git", "dist", "build", ".next", "coverage",
    })
    for _, f in ipairs(files) do
      if utils.file_contains(f, ".get(")
        or utils.file_contains(f, ".post(")
        or utils.file_contains(f, ".put(")
        or utils.file_contains(f, ".delete(")
        or utils.file_contains(f, ".route(")
        or utils.file_contains(f, ".all(")
      then
        local routes = extract_routes(f, language)
        for _, route in ipairs(routes) do
          table.insert(all_routes, route)
        end
      end
    end
  end
  return all_routes
end

-- ---------------------------------------------------------------------------
-- Shared detection helpers (used by both JS and TS provider tables)
-- ---------------------------------------------------------------------------

--- Check if the JavaScript and/or TypeScript tree-sitter parsers are available.
--- Per D-01: partial grammar missing returns ok=true so the provider still activates.
---@return { ok: boolean, message: string|nil }
local function check_prerequisites()
  local js_ok = pcall(vim.treesitter.language.inspect, "javascript")
  local ts_ok = pcall(vim.treesitter.language.inspect, "typescript")

  if not js_ok and not ts_ok then
    return {
      ok = false,
      message = "JavaScript and TypeScript tree-sitter parsers not installed. "
        .. "Run :TSInstall javascript and :TSInstall typescript",
    }
  end

  if not js_ok then
    return {
      ok = true,
      message = "JavaScript tree-sitter parser not installed. Run :TSInstall javascript",
    }
  end

  if not ts_ok then
    return {
      ok = true,
      message = "TypeScript tree-sitter parser not installed. Run :TSInstall typescript",
    }
  end

  return { ok = true }
end

--- Detect if this is an Express.js project by checking dependencies["express"] in package.json.
--- Per D-04: check dependencies only (not devDependencies) to avoid false positives.
--- Per D-05: no active NestJS filter needed — NestJS rarely lists express in its own dependencies.
---@param root string
---@return boolean
local function detect(root)
  local pkg_path = utils.join(root, "package.json")
  if not utils.file_exists(pkg_path) then
    return false
  end

  local content = utils.read_file(pkg_path)
  if not content or content == "" then
    return false
  end

  -- MUST use pcall per Pitfall 1 — json_decode can throw on malformed JSON
  local ok, pkg = pcall(vim.fn.json_decode, content)
  if not ok or type(pkg) ~= "table" then
    return false
  end

  local deps = type(pkg.dependencies) == "table" and pkg.dependencies or {}
  local dev_deps = type(pkg.devDependencies) == "table" and pkg.devDependencies or {}
  return deps["express"] ~= nil or dev_deps["express"] ~= nil
end

--- Find the project root for an Express project.
--- Delegates to ROOT_MARKERS-based search in the provider registry.
---@param startpath string|nil
---@return string
local function find_project_root(startpath)
  return require("nimbleapi.providers").resolve_root(startpath)
end

-- ---------------------------------------------------------------------------
-- JS provider table
-- ---------------------------------------------------------------------------

local JS = {}

JS.name = "express-js"
JS.language = "javascript"
JS.file_extensions = { "js" }
JS.test_patterns = { "*.test.js", "*.spec.js", "**/__tests__/**/*.js", "test/**/*.js" }
JS.path_param_pattern = "{[^}]+}"

-- Shared functions
JS.check_prerequisites = check_prerequisites
JS.detect = detect
JS.find_project_root = find_project_root

--- Find the Express app entry point (stub — implemented in later phase).
---@param _ string
---@return table|nil
JS.find_app = function(_) return nil end

--- Get all routes as a flat list.
---@param root string
---@return table[]
JS.get_all_routes = function(root)
  return get_all_routes_for_ext(root, { "js" }, "javascript")
end

--- Build the route tree.
---@param root string
---@return table|nil
JS.get_route_tree = function(root)
  local routes = JS.get_all_routes(root)
  if not routes or #routes == 0 then return nil end
  return { file = "", var_name = "ExpressApp", routes = routes, routers = {} }
end

--- Extract routes from a single file.
---@param filepath string
---@return table[]
JS.extract_routes = function(filepath)
  return extract_routes(filepath, "javascript")
end

--- Extract router include/mount calls from a file (stub — implemented in later phase).
---@param _ string
---@return table[]
JS.extract_includes = function(_) return {} end

--- Extract test client calls from a buffer (stub — implemented in later phase).
---@param _ integer
---@return table[]
JS.extract_test_calls_buf = function(_) return {} end

-- ---------------------------------------------------------------------------
-- TS provider table
-- ---------------------------------------------------------------------------

local TS = {}

TS.name = "express-ts"
TS.language = "typescript"
TS.file_extensions = { "ts" }
TS.test_patterns = { "*.test.ts", "*.spec.ts", "**/__tests__/**/*.ts", "test/**/*.ts" }
TS.path_param_pattern = "{[^}]+}"

-- Shared functions
TS.check_prerequisites = check_prerequisites
TS.detect = detect
TS.find_project_root = find_project_root

--- Find the Express app entry point (stub — implemented in later phase).
---@param _ string
---@return table|nil
TS.find_app = function(_) return nil end

--- Get all routes as a flat list.
---@param root string
---@return table[]
TS.get_all_routes = function(root)
  return get_all_routes_for_ext(root, { "ts" }, "typescript")
end

--- Build the route tree.
---@param root string
---@return table|nil
TS.get_route_tree = function(root)
  local routes = TS.get_all_routes(root)
  if not routes or #routes == 0 then return nil end
  return { file = "", var_name = "ExpressApp", routes = routes, routers = {} }
end

--- Extract routes from a single file.
---@param filepath string
---@return table[]
TS.extract_routes = function(filepath)
  return extract_routes(filepath, "typescript")
end

--- Extract router include/mount calls from a file (stub — implemented in later phase).
---@param _ string
---@return table[]
TS.extract_includes = function(_) return {} end

--- Extract test client calls from a buffer (stub — implemented in later phase).
---@param _ integer
---@return table[]
TS.extract_test_calls_buf = function(_) return {} end

-- ---------------------------------------------------------------------------
-- Registration — both providers from one module, per D-02
-- ---------------------------------------------------------------------------

require("nimbleapi.providers").register(JS)
require("nimbleapi.providers").register(TS)

return { js = JS, ts = TS }
