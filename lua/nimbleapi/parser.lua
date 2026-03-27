local utils = require("nimbleapi.utils")

local M = {}

--- HTTP methods recognized as route decorators.
local ROUTE_METHODS = {
  get = "GET",
  post = "POST",
  put = "PUT",
  delete = "DELETE",
  patch = "PATCH",
  options = "OPTIONS",
  head = "HEAD",
  trace = "TRACE",
  api_route = "API_ROUTE",
  websocket = "WEBSOCKET",
}

--- HTTP methods recognized in test client calls.
local TEST_CLIENT_METHODS = {
  get = true,
  post = true,
  put = true,
  delete = true,
  patch = true,
  options = true,
  head = true,
}

--- Memoized query cache (query_name -> parsed query).
local query_cache = {}

--- Read and parse a tree-sitter query from our queries/ directory.
---@param name string Query filename without extension (e.g., "fastapi-routes")
---@param language? string Tree-sitter language (default: "python")
---@return vim.treesitter.Query|nil
local function get_query(name, language)
  language = language or "python"
  local cache_key = language .. "/" .. name
  if query_cache[cache_key] then
    return query_cache[cache_key]
  end

  -- Find our query files in the plugin's runtime path
  local query_files = vim.api.nvim_get_runtime_file("queries/" .. language .. "/" .. name .. ".scm", false)
  if #query_files == 0 then
    vim.notify("nimbleapi.nvim: query file not found: queries/" .. language .. "/" .. name .. ".scm", vim.log.levels.ERROR)
    return nil
  end

  local content = utils.read_file(query_files[1])
  if not content then
    vim.notify("nimbleapi.nvim: failed to read query file: " .. query_files[1], vim.log.levels.ERROR)
    return nil
  end

  local query = vim.treesitter.query.parse(language, content)
  query_cache[cache_key] = query
  return query
end

--- Parse a file from disk using string parser.
---@param filepath string
---@param language? string Tree-sitter language (default: "python")
---@return TSNode|nil root, string|nil source
function M.parse_file(filepath, language)
  language = language or "python"
  local source = utils.read_file(filepath)
  if not source then
    return nil, nil
  end

  local ok, ts_parser = pcall(vim.treesitter.get_string_parser, source, language)
  if not ok or not ts_parser then
    return nil, nil
  end
  local trees = ts_parser:parse()
  if not trees or #trees == 0 then
    return nil, nil
  end

  return trees[1]:root(), source
end

--- Parse an open buffer.
---@param bufnr integer
---@param language? string Tree-sitter language (default: "python")
---@return TSNode|nil root, integer|nil bufnr
function M.parse_buffer(bufnr, language)
  language = language or "python"
  local ok, ts_parser = pcall(vim.treesitter.get_parser, bufnr, language)
  if not ok or not ts_parser then
    return nil, nil
  end

  local trees = ts_parser:parse()
  if not trees or #trees == 0 then
    return nil, nil
  end

  return trees[1]:root(), bufnr
end

--- Get text from a node, handling both string source and buffer source.
---@param node TSNode
---@param source string|integer
---@return string
local function get_text(node, source)
  if type(source) == "string" then
    local sr, sc, er, ec = node:range()
    local lines = vim.split(source, "\n", { plain = true })
    if sr == er then
      return lines[sr + 1]:sub(sc + 1, ec)
    end
    local result = { lines[sr + 1]:sub(sc + 1) }
    for i = sr + 2, er do
      table.insert(result, lines[i])
    end
    table.insert(result, lines[er + 1]:sub(1, ec))
    return table.concat(result, "\n")
  else
    return vim.treesitter.get_node_text(node, source)
  end
end

--- Extract route definitions from a file.
---@param filepath string
---@return table[] routes List of { method, path, func, file, line, router_obj }
function M.extract_routes(filepath)
  local root, source = M.parse_file(filepath)
  if not root or not source then
    return {}
  end

  return M._extract_routes_from_tree(root, source, filepath)
end

--- Extract routes from an already-parsed tree.
---@param root TSNode
---@param source string|integer
---@param filepath string
---@return table[]
function M._extract_routes_from_tree(root, source, filepath)
  local query = get_query("fastapi-routes")
  if not query then return {} end
  local routes = {}

  for _, match, _ in query:iter_matches(root, source, 0, -1) do
    local route = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      -- iter_matches returns lists of nodes in Neovim 0.10+
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "router_obj" then
        route.router_obj = get_text(node, source)
      elseif name == "http_method" then
        local method_str = get_text(node, source)
        route.method = ROUTE_METHODS[method_str]
      elseif name == "route_path" then
        -- Node is the string node itself (captures include quote delimiters),
        -- so strip the surrounding quotes. Handles empty strings "" correctly.
        local raw = get_text(node, source)
        route.path = raw:match('^"(.*)"$') or raw:match("^'(.*)'$") or raw
      elseif name == "func_name" then
        route.func = get_text(node, source)
        route.line = node:range() + 1 -- 1-indexed
      elseif name == "route_def" then
        route.def_line = node:range() + 1
      end
    end

    -- Only include valid routes with recognized HTTP methods
    if route.method and route.func then
      -- Default path to "/" if decorator had no path argument
      route.path = route.path or "/"
      table.insert(routes, route)
    end
  end

  return routes
end

--- Extract FastAPI() app assignments from a file.
---@param filepath string
---@return table[] apps List of { var_name, file, line }
function M.extract_fastapi_apps(filepath)
  local root, source = M.parse_file(filepath)
  if not root or not source then
    return {}
  end

  local query = get_query("fastapi-apps")
  if not query then return {} end
  local apps = {}

  for _, match, _ in query:iter_matches(root, source, 0, -1) do
    local app = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "app_var" then
        app.var_name = get_text(node, source)
        app.line = node:range() + 1
      end
    end
    if app.var_name then
      table.insert(apps, app)
    end
  end

  return apps
end

--- Extract include_router() calls from a file.
---@param filepath string
---@return table[] includes List of { app_var, router_ref, prefix, file, line }
function M.extract_include_routers(filepath)
  local root, source = M.parse_file(filepath)
  if not root or not source then
    return {}
  end

  return M._extract_includes_from_tree(root, source, filepath)
end

--- Extract include_router calls from a parsed tree.
---@param root TSNode
---@param source string|integer
---@param filepath string
---@return table[]
function M._extract_includes_from_tree(root, source, filepath)
  local query = get_query("fastapi-includes")
  if not query then return {} end
  local includes = {}

  for _, match, _ in query:iter_matches(root, source, 0, -1) do
    local inc = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "app_var" then
        inc.app_var = get_text(node, source)
      elseif name == "router_module" then
        inc.router_module = get_text(node, source)
      elseif name == "router_attr" then
        inc.router_attr = get_text(node, source)
      elseif name == "router_var" then
        inc.router_var = get_text(node, source)
      elseif name == "include_call" then
        inc.line = node:range() + 1
      end
    end

    -- Build a unified router_ref for downstream resolution
    if inc.router_module and inc.router_attr then
      inc.router_ref = { type = "attribute", object = inc.router_module, attr = inc.router_attr }
    elseif inc.router_var then
      inc.router_ref = { type = "identifier", name = inc.router_var }
    end

    if inc.router_ref then
      -- Extract prefix= keyword argument from the call
      inc.prefix = M._extract_prefix_from_include(root, source, inc.line)
      table.insert(includes, inc)
    end
  end

  return includes
end

--- Extract the prefix= keyword argument from an include_router() call.
--- We do a targeted search near the given line for the keyword_argument.
---@param root TSNode
---@param source string|integer
---@param line integer 1-indexed line number of the include_call
---@return string|nil
function M._extract_prefix_from_include(root, source, line)
  -- Walk the tree to find the call node at this line
  local function find_call_at_line(node)
    if node:type() == "call" then
      local start_line = node:range() + 1
      if start_line == line then
        return node
      end
    end
    for child in node:iter_children() do
      local result = find_call_at_line(child)
      if result then
        return result
      end
    end
    return nil
  end

  local call_node = find_call_at_line(root)
  if not call_node then
    return nil
  end

  -- Look for keyword_argument with name "prefix" in the argument_list
  for child in call_node:iter_children() do
    if child:type() == "argument_list" then
      for arg in child:iter_children() do
        if arg:type() == "keyword_argument" then
          local key_node = arg:field("name")[1]
          local val_node = arg:field("value")[1]
          if key_node and get_text(key_node, source) == "prefix" then
            if val_node then
              local val_text = get_text(val_node, source)
              -- Strip quotes
              return val_text:match('^["\'](.+)["\']$') or val_text
            end
          end
        end
      end
    end
  end

  return nil
end

--- Extract import statements from a file into a lookup table.
---@param filepath string
---@return table import_table Maps local_name -> { module, name, alias, is_relative, level, file }
function M.extract_imports(filepath)
  local root, source = M.parse_file(filepath)
  if not root or not source then
    return {}
  end

  return M._extract_imports_from_tree(root, source, filepath)
end

--- Extract imports from a parsed tree.
---@param root TSNode
---@param source string|integer
---@param filepath string
---@return table
function M._extract_imports_from_tree(root, source, filepath)
  local query = get_query("fastapi-imports")
  if not query then return {} end
  local imports = {}

  for _, match, _ in query:iter_matches(root, source, 0, -1) do
    local entry = { file = filepath }
    local capture_names = {}
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      capture_names[name] = get_text(node, source)

      -- Count dots for relative import prefix
      if name == "prefix" or name == "rel_alias_prefix" then
        local level = 0
        for sub in node:iter_children() do
          if sub:type() == "." then
            level = level + 1
          end
        end
        entry.level = level
        entry.is_relative = true
      end
    end

    -- Absolute import: from X.Y import Z
    if capture_names["module"] and capture_names["imported_name"] then
      local local_name = capture_names["imported_name"]
      imports[local_name] = {
        module = capture_names["module"],
        name = capture_names["imported_name"],
        is_relative = false,
        level = 0,
        file = filepath,
      }
    end

    -- Relative import: from .X import Z
    if capture_names["rel_imported_name"] then
      local local_name = capture_names["rel_imported_name"]
      imports[local_name] = {
        module = capture_names["rel_module"], -- may be nil for bare relative
        name = capture_names["rel_imported_name"],
        is_relative = true,
        level = entry.level or 1,
        file = filepath,
      }
    end

    -- Aliased absolute: from X import Y as Z
    if capture_names["alias_module"] and capture_names["alias_name"] then
      imports[capture_names["alias_name"]] = {
        module = capture_names["alias_module"],
        name = capture_names["alias_original"],
        alias = capture_names["alias_name"],
        is_relative = false,
        level = 0,
        file = filepath,
      }
    end

    -- Aliased relative: from .X import Y as Z
    if capture_names["rel_alias_name"] then
      imports[capture_names["rel_alias_name"]] = {
        module = capture_names["rel_alias_module"],
        name = capture_names["rel_alias_original"],
        alias = capture_names["rel_alias_name"],
        is_relative = true,
        level = entry.level or 1,
        file = filepath,
      }
    end

    -- Plain import: import X.Y.Z
    if capture_names["plain_import"] and not capture_names["module"] then
      local dotted = capture_names["plain_import"]
      -- The local name is the first component (e.g., "app" for "import app.routers.users")
      local first = dotted:match("^([^.]+)")
      imports[first] = {
        module = dotted,
        name = first,
        is_plain_import = true,
        is_relative = false,
        level = 0,
        file = filepath,
      }
    end
  end

  return imports
end

--- Extract test client calls from a file.
---@param filepath string
---@return table[] calls List of { client_var, method, path, file, line }
function M.extract_test_calls(filepath)
  local root, source = M.parse_file(filepath)
  if not root or not source then
    return {}
  end

  return M._extract_test_calls_from_tree(root, source, filepath)
end

--- Extract test client calls from a buffer.
---@param bufnr integer
---@return table[]
function M.extract_test_calls_buf(bufnr)
  local root = M.parse_buffer(bufnr)
  if not root then
    return {}
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)
  return M._extract_test_calls_from_tree(root, bufnr, filepath)
end

---@param root TSNode
---@param source string|integer
---@param filepath string
---@return table[]
function M._extract_test_calls_from_tree(root, source, filepath)
  local query = get_query("fastapi-testclient")
  if not query then return {} end
  local calls = {}

  for _, match, _ in query:iter_matches(root, source, 0, -1) do
    local call = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "client_var" then
        call.client_var = get_text(node, source)
      elseif name == "http_method" then
        local m = get_text(node, source)
        if TEST_CLIENT_METHODS[m] then
          call.method = m:upper()
        end
      elseif name == "test_path" then
        call.path = get_text(node, source)
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

--- Get text from a node, handling both string source and buffer source.
--- Public accessor for providers that run their own queries.
---@param node TSNode
---@param source string|integer
---@return string
function M.get_text(node, source)
  return get_text(node, source)
end

--- Public accessor for get_query (used by providers that run their own queries).
---@param name string
---@param language? string
---@return vim.treesitter.Query|nil
function M.get_query_public(name, language)
  return get_query(name, language)
end

return M
