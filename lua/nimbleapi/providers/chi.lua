local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")

local M = {}

M.name = "chi"
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

--- HTTP method lookup table for Chi route methods.
--- Keys are Go method names (mixed-case as used in Chi API).
--- Values are normalized HTTP method strings.
local CHI_METHODS = {
  Get         = "GET",
  Post        = "POST",
  Put         = "PUT",
  Delete      = "DELETE",
  Patch       = "PATCH",
  Options     = "OPTIONS",
  Head        = "HEAD",
  Connect     = "CONNECT",
  Trace       = "TRACE",
  Handle      = "ANY",
  HandleFunc  = "ANY",
  Mount       = "MOUNT",
  -- Route and Group are intentionally absent — they are prefix containers, not leaf routes
}

--- Strip surrounding quotes from an interpreted_string_literal token.
---@param text string
---@return string
local function strip_quotes(text)
  return text:match('^"(.*)"$') or text:match("^'(.*)'$") or text
end

--- Walk the AST parent chain from a node and collect all enclosing r.Route() path prefixes.
--- Chi's closure-based nesting: r.Route("/prefix", func(r chi.Router) { ... })
--- Each Route ancestor in the parent chain contributes one prefix segment.
--- r.Group ancestors contribute zero prefix (middleware-only containers).
---
--- Algorithm:
---   Start at start_node, walk node:parent() upward.
---   When a call_expression ancestor has method "Route" in its selector_expression,
---   extract the first interpreted_string_literal argument and prepend it to the prefix list.
---   Stop after 50 levels (cycle/depth guard).
---
---@param start_node TSNode The route_def node (the call_expression of the route registration)
---@param source string The file source text (used for get_text calls)
---@return string[] prefixes Ordered list of path segments, outermost first
local function collect_route_prefixes(start_node, source)
  local prefixes = {}
  local current = start_node:parent()
  local depth = 0
  while current and depth < 50 do
    if current:type() == "call_expression" then
      local fn_node = current:field("function")
      if fn_node and fn_node:type() == "selector_expression" then
        local field_node = fn_node:field("field")
        if field_node then
          local method_name = parser.get_text(field_node, source)
          if method_name == "Route" then
            -- This is an enclosing r.Route("/prefix", ...) — collect its path argument
            local args_node = current:field("arguments")
            if args_node then
              for i = 0, args_node:child_count() - 1 do
                local arg = args_node:child(i)
                if arg and arg:type() == "interpreted_string_literal" then
                  local prefix = strip_quotes(parser.get_text(arg, source))
                  table.insert(prefixes, 1, prefix) -- prepend: we're walking inside-out
                  break
                end
              end
            end
          end
          -- method_name == "Group": explicitly skip — zero prefix contribution (CHI-07)
        end
      end
    end
    current = current:parent()
    depth = depth + 1
  end
  return prefixes
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

--- Detect if this is a Chi project.
---@param root string
---@return boolean
function M.detect(root)
  local gomod = utils.join(root, "go.mod")
  if utils.file_exists(gomod) then
    if utils.file_contains(gomod, "github.com/go-chi/chi") then
      return true
    end
  end
  return false
end

--- Find the app entry point (stub — Chi does not need an entry point for route scanning).
---@param root string
---@return table|nil
function M.find_app(root)
  return nil
end

--- Extract routes from a single Go file.
--- Uses chi-routes.scm query to capture all route registrations and sub-router containers.
--- For each route, walks the AST parent chain to collect enclosing r.Route() prefixes (CHI-05).
--- Route/Group calls are skipped (not emitted as routes).
--- Mount calls are emitted as MOUNT entries (CHI-06).
---@param filepath string Absolute path to a .go file
---@return table[] routes List of { method, path, func, file, line } records
function M.extract_routes(filepath)
  local root_node, source = parser.parse_file(filepath, "go")
  if not root_node or not source then
    return {}
  end

  local ok, routes_query = pcall(parser.get_query_public, "chi-routes", "go")
  if not ok or not routes_query then
    return {}
  end

  local routes = {}
  for _, match, _ in routes_query:iter_matches(root_node, source, 0, -1) do
    local router_obj_text  = nil
    local http_method_text = nil
    local method_arg_text  = nil
    local route_path_text  = nil
    local func_name_text   = nil
    local route_def_node   = nil

    for id, nodes in pairs(match) do
      local name = routes_query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "router_obj" then
        router_obj_text = parser.get_text(node, source)
      elseif name == "http_method" then
        http_method_text = parser.get_text(node, source)
      elseif name == "_method_arg" then
        method_arg_text = strip_quotes(parser.get_text(node, source))
      elseif name == "route_path" then
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

    -- Skip Route and Group calls — they are sub-router containers, not leaf route entries
    -- Route: handled by parent-chain walk (CHI-05)
    -- Group: zero prefix contribution, middleware-only (CHI-07)
    if http_method_text == "Route" or http_method_text == "Group" then
      goto continue
    end

    -- Determine the HTTP method
    local method = nil
    if http_method_text == "Method" or http_method_text == "MethodFunc" then
      -- Method/MethodFunc: HTTP verb is the first string argument (CHI-04)
      if method_arg_text then
        method = method_arg_text:upper()
      end
    else
      -- Direct shortcuts, Handle, HandleFunc, Mount
      method = CHI_METHODS[http_method_text]
    end

    if method and route_path_text and func_name_text ~= nil and route_def_node then
      -- Collect enclosing Route prefixes via parent-chain walk (CHI-05)
      local prefixes = collect_route_prefixes(route_def_node, source)
      local full_path = table.concat(prefixes, "") .. route_path_text

      -- Normalize path parameters and collapse double slashes
      full_path = normalize_path(full_path)
      full_path = full_path:gsub("//+", "/")
      if full_path == "" then
        full_path = "/"
      end

      local row, _, _, _ = route_def_node:range()
      table.insert(routes, {
        method = method,
        path   = full_path,
        func   = func_name_text,
        file   = filepath,
        line   = row + 1, -- tree-sitter rows are 0-indexed
      })
    end

    ::continue::
  end

  -- Sort routes by line number for predictable output
  table.sort(routes, function(a, b)
    return a.line < b.line
  end)

  return routes
end

--- Get all routes across all Go files in a Chi project.
--- Scans all *.go files (excluding vendor, testdata, node_modules, .git),
--- pre-filtering to files that likely contain Chi route registrations.
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
    -- Pre-filter: only parse files that likely contain Chi route or router calls.
    -- "go-chi/chi" catches the import line in files that use chi directly.
    -- Method calls catch files using a chi router variable without explicit "chi" reference.
    if
      utils.file_contains(f, "go-chi/chi")
      or utils.file_contains(f, ".Get(")
      or utils.file_contains(f, ".Post(")
      or utils.file_contains(f, ".Route(")
      or utils.file_contains(f, ".Mount(")
      or utils.file_contains(f, ".Handle(")
      or utils.file_contains(f, ".Method(")
    then
      local file_routes = M.extract_routes(f)
      for _, route in ipairs(file_routes) do
        table.insert(all_routes, route)
      end
    end
  end

  return all_routes
end

--- Build the route tree for the Chi project (simple wrapper over get_all_routes).
---@param root string
---@return table|nil
function M.get_route_tree(root)
  local routes = M.get_all_routes(root)
  if not routes or #routes == 0 then
    return nil
  end
  return { file = "", var_name = "ChiApp", routes = routes, routers = {} }
end

--- Extract router composition calls from a file.
--- Chi has no cross-file router composition via include_router,
--- so this always returns an empty list.
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

  local ok, query = pcall(parser.get_query_public, "chi-testclient", "go")
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
