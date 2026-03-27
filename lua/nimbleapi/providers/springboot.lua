local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")

local M = {}

M.name = "spring"
M.language = "java"
M.file_extensions = { "java" }
M.test_patterns = { "*Test.java", "*Tests.java", "*IT.java", "src/test/**/*.java" }
M.path_param_pattern = "{[^}]+}"

--- Check if the Java tree-sitter parser is available.
---@return { ok: boolean, message: string|nil }
function M.check_prerequisites()
  local ok = pcall(vim.treesitter.language.inspect, "java")
  if not ok then
    return { ok = false, message = "Java tree-sitter parser not installed. Run :TSInstall java" }
  end
  return { ok = true }
end

--- Annotation name -> HTTP method mapping.
local ANNOTATION_METHODS = {
  GetMapping = "GET",
  PostMapping = "POST",
  PutMapping = "PUT",
  DeleteMapping = "DELETE",
  PatchMapping = "PATCH",
  RequestMapping = "REQUEST_MAPPING", -- resolved from method= attribute
}

--- RequestMethod enum values -> HTTP method.
local REQUEST_METHODS = {
  GET = "GET",
  POST = "POST",
  PUT = "PUT",
  DELETE = "DELETE",
  PATCH = "PATCH",
  OPTIONS = "OPTIONS",
  HEAD = "HEAD",
  TRACE = "TRACE",
}

--- MockMvc/WebTestClient method names -> HTTP method.
local TEST_CLIENT_METHODS = {
  get = "GET",
  post = "POST",
  put = "PUT",
  delete = "DELETE",
  patch = "PATCH",
  options = "OPTIONS",
  head = "HEAD",
}

--- Strip surrounding quotes from a string literal.
---@param text string
---@return string
local function strip_quotes(text)
  return text:match('^"(.*)"$') or text:match("^'(.*)'$") or text
end

function M.reset()
  return
end

--- Find project root by walking up for pom.xml, build.gradle, or .git.
---@param startpath string|nil
---@return string
function M.find_project_root(startpath)
  local markers = { "pom.xml", "build.gradle", "build.gradle.kts", "settings.gradle", ".git" }
  return utils.find_project_root(startpath, markers)
end

--- Dependency markers that indicate a Spring web project (Boot or plain Framework).
local SPRING_WEB_MARKERS = {
  "spring-boot-starter-web",
  "spring-boot-starter-webflux",
  "spring-webmvc",
  "spring-web",
}

--- Detect if this is a Spring project (Boot or plain Spring MVC).
---@param root string
---@return boolean
function M.detect(root)
  -- Check pom.xml
  local pom = utils.join(root, "pom.xml")
  if utils.file_exists(pom) then
    for _, marker in ipairs(SPRING_WEB_MARKERS) do
      if utils.file_contains(pom, marker) then
        return true
      end
    end
  end

  -- Check build.gradle / build.gradle.kts
  for _, name in ipairs({ "build.gradle", "build.gradle.kts" }) do
    local gradle = utils.join(root, name)
    if utils.file_exists(gradle) then
      for _, marker in ipairs(SPRING_WEB_MARKERS) do
        if utils.file_contains(gradle, marker) then
          return true
        end
      end
    end
  end

  -- Fallback: scan for @RestController / @Controller annotations
  local java_files = utils.glob_files(root, "src/main/java/**/*.java", {
    "node_modules", ".git", "target", "build",
  })
  for _, f in ipairs(java_files) do
    if utils.file_contains(f, "@RestController") or utils.file_contains(f, "@Controller") then
      return true
    end
  end

  return false
end

--- Find the application entry point.
--- Tries @SpringBootApplication first, falls back to the first @Controller/@RestController.
---@param root string
---@return table|nil app { file, class_name, line }
function M.find_app(root)
  local java_files = utils.glob_files(root, "src/main/java/**/*.java", {
    "node_modules", ".git", "target", "build",
  })

  -- Pass 1: Look for @SpringBootApplication (preferred — it's the canonical entry point)
  for _, f in ipairs(java_files) do
    if f:match("Application%.java$") and utils.file_contains(f, "@SpringBootApplication") then
      local apps = M._extract_apps(f)
      if #apps > 0 then
        return apps[1]
      end
    end
  end

  for _, f in ipairs(java_files) do
    if utils.file_contains(f, "@SpringBootApplication") then
      local apps = M._extract_apps(f)
      if #apps > 0 then
        return apps[1]
      end
    end
  end

  -- Pass 2: No Boot app found — use the first controller class as the anchor
  for _, f in ipairs(java_files) do
    if utils.file_contains(f, "@RestController") or utils.file_contains(f, "@Controller") then
      return { file = f, class_name = utils.basename(f):gsub("%.java$", ""), line = 1 }
    end
  end

  return nil
end

--- Extract @SpringBootApplication classes from a file.
---@param filepath string
---@return table[]
function M._extract_apps(filepath)
  local root_node, source = parser.parse_file(filepath, "java")
  if not root_node or not source then
    return {}
  end

  local ok, query = pcall(parser.get_query_public, "springboot-apps", "java")
  if not ok or not query then
    return {}
  end

  local apps = {}
  for _, match, _ in query:iter_matches(root_node, source, 0, -1) do
    local app = { file = filepath }
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "app_class" then
        app.class_name = parser.get_text(node, source)
        app.line = node:range() + 1
      end
    end
    if app.class_name then
      table.insert(apps, app)
    end
  end

  return apps
end

--- Extract the class-level @RequestMapping prefix from a controller file.
---@param root_node TSNode
---@param source string
---@return string prefix, string|nil class_name
local function extract_class_prefix(root_node, source)
  local ok, query = pcall(parser.get_query_public, "springboot-controllers", "java")
  if not ok or not query then
    return "", nil
  end

  local best_prefix = ""
  local best_class_name = nil

  for _, match, _ in query:iter_matches(root_node, source, 0, -1) do
    local prefix = ""
    local class_name = nil
    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      if name == "class_prefix" then
        prefix = strip_quotes(parser.get_text(node, source))
      elseif name == "class_name" then
        class_name = parser.get_text(node, source)
      end
    end
    -- Prefer match with a non-empty prefix (@RequestMapping("/api"))
    -- over bare @RestController/@Controller (which has no prefix)
    if class_name then
      best_class_name = best_class_name or class_name
    end
    if prefix ~= "" then
      return prefix, class_name or best_class_name
    end
  end

  return best_prefix, best_class_name
end

--- Extract routes from a single Java file (two-pass: class prefix + method annotations).
---@param filepath string
---@return table[]
function M.extract_routes(filepath)
  local root_node, source = parser.parse_file(filepath, "java")
  if not root_node or not source then
    return {}
  end

  -- Pass 1: get class-level prefix
  local class_prefix = extract_class_prefix(root_node, source)

  -- Pass 2: get method-level routes
  local ok, query = pcall(parser.get_query_public, "springboot-routes", "java")
  if not ok or not query then
    return {}
  end

  -- Collect all matches keyed by func line, merging multiple pattern matches
  -- (e.g., Pattern 2 gives path, Pattern 4 gives method= for the same @RequestMapping)
  local by_line = {}

  for _, match, _ in query:iter_matches(root_node, source, 0, -1) do
    local entry = {}
    local request_method_value = nil

    for id, nodes in pairs(match) do
      local name = query.captures[id]
      local node = type(nodes) == "table" and nodes[1] or nodes
      local text = parser.get_text(node, source)

      if name == "http_method" then
        entry.annotation = text
        entry.method = ANNOTATION_METHODS[text]
      elseif name == "route_path" then
        entry.path = strip_quotes(text)
      elseif name == "func_name" then
        entry.func = text
        entry.line = node:range() + 1
      elseif name == "route_def" then
        entry.def_line = node:range() + 1
      elseif name == "_request_method" then
        request_method_value = text
      end
    end

    if entry.func and entry.line then
      local key = entry.line
      if not by_line[key] then
        by_line[key] = { file = filepath }
      end
      local route = by_line[key]
      -- Merge: non-nil values from this match override
      if entry.method then
        route._annotation = entry.annotation
        route._raw_method = entry.method
      end
      if entry.path then
        route.path = entry.path
      end
      route.func = entry.func
      route.line = entry.line
      if entry.def_line then
        route.def_line = entry.def_line
      end
      if request_method_value then
        route._request_method = request_method_value
      end
    end
  end

  -- Flatten merged entries into route list
  local routes = {}
  for _, route in pairs(by_line) do
    local method = route._raw_method
    -- Resolve RequestMapping method= to actual HTTP method
    if method == "REQUEST_MAPPING" then
      if route._request_method and REQUEST_METHODS[route._request_method] then
        method = REQUEST_METHODS[route._request_method]
      else
        method = "GET" -- default for @RequestMapping without method=
      end
    end
    route.method = method
    route._raw_method = nil
    route._annotation = nil
    route._request_method = nil

    if route.method and route.func then
      route.path = route.path or ""
      local full_path = class_prefix .. route.path
      full_path = full_path:gsub("//+", "/")
      if full_path == "" then
        full_path = "/"
      end
      route.path = full_path
      table.insert(routes, route)
    end
  end

  -- Sort by line number for stable output
  table.sort(routes, function(a, b) return a.line < b.line end)

  return routes
end

--- Get all routes across the project.
---@param root string
---@return table[]
function M.get_all_routes(root)
  local java_files = utils.glob_files(root, "src/main/java/**/*.java", {
    "node_modules", ".git", "target", "build",
  })

  local all_routes = {}

  -- Pre-filter: only parse files likely to be controllers
  for _, f in ipairs(java_files) do
    if utils.file_contains(f, "Mapping") or utils.file_contains(f, "@Controller") then
      local routes = M.extract_routes(f)
      for _, route in ipairs(routes) do
        table.insert(all_routes, route)
      end
    end
  end

  return all_routes
end

--- Build a route tree (Spring Boot doesn't use cross-file composition like FastAPI).
---@param root string
---@return table|nil
function M.get_route_tree(root)
  local app = M.find_app(root)
  local routes = M.get_all_routes(root)

  if #routes == 0 and not app then
    return nil
  end

  return {
    file = app and app.file or "",
    var_name = app and app.class_name or "SpringApp",
    routes = routes,
    routers = {},
  }
end

--- No cross-file includes in annotation-based Spring Boot.
---@param _filepath string
---@return table[]
function M.extract_includes(_filepath)
  return {}
end

--- Extract test client calls from a buffer.
---@param bufnr integer
---@return table[]
function M.extract_test_calls_buf(bufnr)
  local root_node, buf = parser.parse_buffer(bufnr, "java")
  if not root_node then
    return {}
  end

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  local ok, query = pcall(parser.get_query_public, "springboot-testclient", "java")
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

      if name == "client_var" then
        call.client_var = text
      elseif name == "http_method" then
        local m = TEST_CLIENT_METHODS[text]
        if m then
          call.method = m
        end
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

-- Register with the provider registry
require("nimbleapi.providers").register(M)

return M
