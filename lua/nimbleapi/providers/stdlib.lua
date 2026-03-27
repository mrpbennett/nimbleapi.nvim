local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")

local M = {}

M.name = "stdlib"
M.language = "go"
M.file_extensions = { "go" }
M.test_patterns = { "*_test.go", "**/*_test.go" }
M.path_param_pattern = "{[^}]+}"

--- Normalize Go path parameters to {param} style.
--- :param -> {param}, *wildcard -> {wildcard}, {id:[0-9]+} -> {id}, {$} -> stripped
---@param path string
---@return string
local function normalize_path(path)
  -- Strip regex suffix inside braces: {id:[0-9]+} -> {id}
  path = path:gsub("{([^}:]+):[^}]*}", "{%1}")
  -- Colon-style params: :param -> {param}
  path = path:gsub(":([%w_]+)", "{%1}")
  -- Wildcard: *wildcard -> {wildcard}
  path = path:gsub("%*([%w_]+)", "{%1}")
  -- stdlib end-anchor: {$} -> strip entirely
  path = path:gsub("{%$}", "")
  return path
end

M.normalize_path = normalize_path

--- Strip surrounding quotes from an interpreted_string_literal token.
---@param text string
---@return string
local function strip_quotes(text)
  return text:match('^"(.*)"$') or text:match("^'(.*)'$") or text
end

--- Set of valid HTTP method verbs used to identify Go 1.22+ method-prefixed paths.
--- Keys are uppercase method names; values are true.
local KNOWN_METHODS = {
  GET = true, POST = true, PUT = true, DELETE = true,
  PATCH = true, OPTIONS = true, HEAD = true, CONNECT = true, TRACE = true,
}

--- Split a Go route path string into HTTP method and path.
--- Pre-1.22: "/path" -> ("ANY", "/path")
--- Go 1.22+: "GET /path" -> ("GET", "/path")
--- Falls back to ("ANY", raw_path) if the prefix is not a known HTTP method.
---@param raw_path string The route path string (already stripped of quotes)
---@return string method The HTTP method ("GET", "POST", ..., or "ANY")
---@return string path The URL path ("/users/{id}", etc.)
local function split_method_path(raw_path)
  local space = raw_path:find(" ")
  if space then
    local verb = raw_path:sub(1, space - 1):upper()
    if KNOWN_METHODS[verb] then
      return verb, raw_path:sub(space + 1)
    end
  end
  -- Pre-1.22 or unrecognized prefix: treat whole string as path with method ANY
  return "ANY", raw_path
end

--- Check if the Go tree-sitter parser is available.
---@return { ok: boolean, message: string|nil }
function M.check_prerequisites()
  local ok = pcall(vim.treesitter.language.inspect, "go")
  if not ok then
    return { ok = false, message = "Go tree-sitter parser not installed. Run :TSInstall go" }
  end
  return { ok = true }
end

--- Detect if this is a net/http stdlib project.
--- Detection strategy: negative exclusion (no known frameworks in go.mod)
--- + source-scan confirmation (HandleFunc or .Handle calls found in at least one .go file).
--- This prevents false positives for Go projects that use no HTTP routing at all.
---@param root string
---@return boolean
function M.detect(root)
  local gomod = utils.join(root, "go.mod")
  if not utils.file_exists(gomod) then
    return false
  end
  -- Negative exclusion: if any known framework is present, this is not stdlib
  local known_frameworks = {
    "github.com/gin-gonic/gin",
    "github.com/labstack/echo",
    "github.com/go-chi/chi",
    "github.com/gofiber/fiber",
  }
  for _, fw in ipairs(known_frameworks) do
    if utils.file_contains(gomod, fw) then
      return false
    end
  end
  -- Source-scan fallback: confirm this Go project actually uses net/http routing.
  -- Look for HandleFunc( or .Handle( in any .go source file.
  -- net/http is stdlib so it never appears in go.mod — source scan is the only signal.
  local go_files = utils.glob_files(root, "**/*.go", { "vendor", "testdata", ".git" })
  for _, f in ipairs(go_files) do
    if utils.file_contains(f, "HandleFunc(") or utils.file_contains(f, ".Handle(") then
      return true
    end
  end
  return false
end

--- Find the app entry point (stub — full implementation in a later phase).
---@param root string
---@return table|nil
function M.find_app(root)
  return nil
end

--- Extract routes from a single Go file using stdlib-routes.scm query.
--- Handles both pre-1.22 ("/path" -> ANY) and Go 1.22+ ("GET /path" -> GET + /path) patterns.
--- Captures HandleFunc and Handle calls on any receiver (mux, http, s.mux, etc.).
---@param filepath string Absolute path to a .go file
---@return table[] routes List of { method, path, func, file, line } records
function M.extract_routes(filepath)
  local root_node, source = parser.parse_file(filepath, "go")
  if not root_node or not source then
    return {}
  end

  local ok, routes_query = pcall(parser.get_query_public, "stdlib-routes", "go")
  if not ok or not routes_query then
    return {}
  end

  local routes = {}
  for _, match, _ in routes_query:iter_matches(root_node, source, 0, -1) do
    local route_path_text = nil
    local func_name_text  = nil
    local route_def_node  = nil

    for id, nodes in pairs(match) do
      local name = routes_query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes

      if name == "route_path" then
        route_path_text = strip_quotes(parser.get_text(node, source))
      elseif name == "func_name" then
        -- Guard: anonymous inline handlers produce func_literal nodes — use empty string
        -- to avoid capturing multi-line function bodies as the handler name (Gin lesson)
        if node:type() == "func_literal" then
          func_name_text = ""
        else
          func_name_text = parser.get_text(node, source)
        end
      elseif name == "route_def" then
        route_def_node = node
      end
    end

    if route_path_text and func_name_text ~= nil and route_def_node then
      -- Split method and path: handles pre-1.22 and Go 1.22+ dual-era patterns
      local method, path = split_method_path(route_path_text)

      -- Normalize path parameters ({id:[0-9]+} -> {id}, :param -> {param}, {$} -> stripped)
      path = normalize_path(path)
      path = path:gsub("//+", "/")
      if path == "" then
        path = "/"
      end

      local row = route_def_node:range()
      table.insert(routes, {
        method = method,
        path   = path,
        func   = func_name_text,
        file   = filepath,
        line   = row + 1, -- tree-sitter rows are 0-indexed
      })
    end
  end

  -- Sort routes by line number for predictable output
  table.sort(routes, function(a, b)
    return a.line < b.line
  end)

  return routes
end

--- Get all routes across all Go files in a net/http stdlib project.
--- Scans all *.go files (excluding vendor, testdata, node_modules, .git),
--- pre-filtering to files that likely contain route registrations.
---@param root string Project root directory
---@return table[] routes Flat list of { method, path, func, file, line } records
function M.get_all_routes(root)
  local go_files = utils.glob_files(root, "**/*.go", {
    "vendor",
    "testdata",
    "node_modules",
    ".git",
  })

  local all_routes = {}
  for _, f in ipairs(go_files) do
    -- Pre-filter: only parse files that likely contain route registrations.
    -- "HandleFunc(" catches both mux.HandleFunc and http.HandleFunc.
    -- ".Handle(" catches mux.Handle and s.mux.Handle (with leading dot).
    if utils.file_contains(f, "HandleFunc(") or utils.file_contains(f, ".Handle(") then
      local file_routes = M.extract_routes(f)
      for _, route in ipairs(file_routes) do
        table.insert(all_routes, route)
      end
    end
  end

  return all_routes
end

--- Build the route tree for the stdlib project (simple wrapper over get_all_routes).
---@param root string
---@return table|nil
function M.get_route_tree(root)
  local routes = M.get_all_routes(root)
  if not routes or #routes == 0 then
    return nil
  end
  return { file = "", var_name = "StdlibApp", routes = routes, routers = {} }
end

--- Extract router composition calls from a file (stub — full implementation in a later phase).
---@param filepath string
---@return table[]
function M.extract_includes(filepath)
  return {}
end

--- Extract test client calls from a buffer.
--- Parses the buffer for httptest.NewRequest("METHOD", "/path", ...) calls
--- and returns a list of { method, path, line, file } records for codelens matching.
---@param bufnr integer
---@return table[] calls List of { method, path, line, file } records
function M.extract_test_calls_buf(bufnr)
  local root_node, buf = parser.parse_buffer(bufnr, "go")
  if not root_node then
    return {}
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local ok, query = pcall(parser.get_query_public, "stdlib-testclient", "go")
  if not ok or not query then
    return {}
  end

  local calls = {}
  for _, match, _ in query:iter_matches(root_node, buf, 0, -1) do
    local call = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      local text = parser.get_text(node, buf)

      if name == "http_method" then
        call.method = strip_quotes(text)
      elseif name == "test_path" then
        call.path = strip_quotes(text)
      elseif name == "test_call" then
        call.line = node:range() + 1
      end
    end

    if call.method and call.path then
      table.insert(calls, call)
    end
  end

  return calls
end

--- Find project root by walking up from startpath.
---@param startpath string|nil
---@return string
function M.find_project_root(startpath)
  local markers = { "go.mod", ".git" }
  return require("nimbleapi.utils").find_project_root(
    startpath or vim.fn.getcwd(),
    markers
  )
end

-- Register with the provider registry
require("nimbleapi.providers").register(M)

return M
