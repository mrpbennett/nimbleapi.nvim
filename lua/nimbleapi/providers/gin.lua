local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")

local M = {}

M.name = "gin"
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

--- HTTP method lookup table for Gin route shortcuts.
--- Keys are Go method names; values are normalized HTTP method strings.
--- Any maps to "ANY" per D-01 (single entry, not expanded).
local GIN_METHODS = {
	GET = "GET",
	POST = "POST",
	PUT = "PUT",
	DELETE = "DELETE",
	PATCH = "PATCH",
	OPTIONS = "OPTIONS",
	HEAD = "HEAD",
	Any = "ANY",
}

--- Strip surrounding quotes from a string literal.
---@param text string
---@return string
local function strip_quotes(text)
	return text:match('^"(.*)"$') or text:match("^'(.*)'$") or text
end

--- Recursively resolve the full prefix chain for a group variable.
--- Returns concatenated prefix from root router to this var.
--- Cycle guard via visited set prevents infinite recursion.
---@param var_name string
---@param groups table Map of var_name -> { prefix: string, parent: string }
---@param visited table Set of var_names already in the resolution chain
---@return string
local function resolve_prefix(var_name, groups, visited)
	if not groups[var_name] then
		return ""
	end
	if visited[var_name] then
		return ""
	end -- cycle guard (Research pitfall 5)
	visited[var_name] = true
	local entry = groups[var_name]
	local parent_prefix = resolve_prefix(entry.parent, groups, visited)
	return parent_prefix .. entry.prefix
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

--- Detect if this is a Gin project.
---@param root string
---@return boolean
function M.detect(root)
	local gomod = utils.join(root, "go.mod")
	if utils.file_exists(gomod) then
		if utils.file_contains(gomod, "github.com/gin-gonic/gin") then
			return true
		end
	end
	return false
end

--- Find the app entry point (stub — Gin does not need an entry point for route scanning).
---@param root string
---@return table|nil
function M.find_app(root)
	return nil
end

--- Extract routes from a single Go file using a two-pass algorithm.
--- Pass 1: Collect RouterGroup variable assignments (gin-groups.scm).
--- Pass 2: Extract route calls and resolve their full prefix chains (gin-routes.scm).
---@param filepath string Absolute path to a .go file
---@return table[] routes List of { method, path, func, file, line } records
function M.extract_routes(filepath)
	local root_node, source = parser.parse_file(filepath, "go")
	if not root_node or not source then
		return {}
	end

	-- Pass 1: Collect all RouterGroup variable assignments in this file.
	-- groups[var_name] = { prefix = "/prefix", parent = "parent_var" }
	-- Per D-02: file-scope collection (cross-function collision is theoretically possible
	-- but rare in practice and explicitly accepted).
	local groups = {}
	local ok_groups, groups_query = pcall(parser.get_query_public, "gin-groups", "go")
	if ok_groups and groups_query then
		for _, match, _ in groups_query:iter_matches(root_node, source, 0, -1) do
			local group_var_text = nil
			local router_obj_text = nil
			local route_path_text = nil

			for id, nodes in pairs(match) do
				local name = groups_query.captures[id]
				local node = type(nodes) == "table" and nodes[1] or nodes
				if name == "group_var" then
					group_var_text = parser.get_text(node, source)
				elseif name == "router_obj" then
					router_obj_text = parser.get_text(node, source)
				elseif name == "route_path" then
					route_path_text = strip_quotes(parser.get_text(node, source))
				end
			end

			if group_var_text and router_obj_text and route_path_text then
				groups[group_var_text] = { prefix = route_path_text, parent = router_obj_text }
			end
		end
	end

	-- Pass 2: Extract route calls and apply resolved group prefixes.
	local routes = {}
	local ok_routes, routes_query = pcall(parser.get_query_public, "gin-routes", "go")
	if not ok_routes or not routes_query then
		return {}
	end

	for _, match, _ in routes_query:iter_matches(root_node, source, 0, -1) do
		local router_obj_text = nil
		local http_method_text = nil
		local handle_method_text = nil
		local route_path_text = nil
		local func_name_text = nil
		local route_def_line = nil

		for id, nodes in pairs(match) do
			local name = routes_query.captures[id]
			local node = type(nodes) == "table" and nodes[1] or nodes
			if name == "router_obj" then
				router_obj_text = parser.get_text(node, source)
			elseif name == "http_method" then
				http_method_text = parser.get_text(node, source)
			elseif name == "_handle_method" then
				handle_method_text = strip_quotes(parser.get_text(node, source))
			elseif name == "route_path" then
				route_path_text = strip_quotes(parser.get_text(node, source))
			elseif name == "func_name" then
				if node:type() == "func_literal" then
					func_name_text = ""
				else
					func_name_text = parser.get_text(node, source)
				end
			elseif name == "route_def" then
				local row, _, _, _ = node:range()
				route_def_line = row + 1 -- tree-sitter rows are 0-indexed
			end
		end

		-- Determine the HTTP method
		local method = nil
		if http_method_text == "Handle" then
			-- router.Handle("GET", "/path", handler) — method is the first string argument
			if handle_method_text then
				method = handle_method_text:upper()
			end
		else
			-- Method shortcut (GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD, Any)
			method = GIN_METHODS[http_method_text]
		end

		-- Skip if method not recognized (filters out non-route calls like .Use(), .Static(), etc.)
		if method and route_path_text and func_name_text and router_obj_text then
			-- Resolve full path with group prefix chain
			local prefix = resolve_prefix(router_obj_text, groups, {})
			local full_path = prefix .. route_path_text

			-- Normalize path parameters and collapse double slashes
			full_path = normalize_path(full_path)
			full_path = full_path:gsub("//+", "/")
			if full_path == "" then
				full_path = "/"
			end

			table.insert(routes, {
				method = method,
				path = full_path,
				func = func_name_text,
				file = filepath,
				line = route_def_line or 0,
			})
		end
	end

	-- Sort routes by line number for predictable output
	table.sort(routes, function(a, b)
		return a.line < b.line
	end)

	return routes
end

--- Get all routes across all Go files in a Gin project.
--- Scans all *.go files (excluding vendor, testdata, node_modules, .git),
--- pre-filtering to files that likely contain Gin route registrations.
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
		-- Pre-filter: only parse files that likely contain Gin route or group calls.
		-- "gin." catches gin.Default(), gin.New() — the engine setup.
		-- The method calls catch files using a router variable without "gin." import reference.
		if
			utils.file_contains(f, "gin.")
			or utils.file_contains(f, ".GET(")
			or utils.file_contains(f, ".POST(")
			or utils.file_contains(f, ".Handle(")
			or utils.file_contains(f, ".Group(")
		then
			local routes = M.extract_routes(f)
			for _, route in ipairs(routes) do
				table.insert(all_routes, route)
			end
		end
	end

	return all_routes
end

--- Build the route tree for the Gin project (simple wrapper over get_all_routes).
---@param root string
---@return table|nil
function M.get_route_tree(root)
	local routes = M.get_all_routes(root)
	if not routes or #routes == 0 then
		return nil
	end
	return { file = "", var_name = "GinApp", routes = routes, routers = {} }
end

--- Extract router composition calls from a file.
--- Gin has no cross-file router composition (unlike FastAPI's include_router),
--- so this always returns an empty list.
---@param filepath string
---@return table[]
function M.extract_includes(filepath)
	return {}
end

--- Extract test client calls from a buffer.
--- Parses the buffer for http.NewRequest("METHOD", "/path", ...) calls
--- and returns a list of { method, path, line, file } records for codelens matching.
---@param bufnr integer
---@return table[] calls List of { method, path, line, file } records
function M.extract_test_calls_buf(bufnr)
	local root_node, buf = parser.parse_buffer(bufnr, "go")
	if not root_node then
		return {}
	end

	local filepath = vim.api.nvim_buf_get_name(bufnr)

	local ok, query = pcall(parser.get_query_public, "gin-testclient", "go")
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
	return require("nimbleapi.utils").find_project_root(startpath or vim.fn.getcwd(), markers)
end

-- Register with the provider registry
require("nimbleapi.providers").register(M)

return M
