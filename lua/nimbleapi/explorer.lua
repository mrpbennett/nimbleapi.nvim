local utils = require("nimbleapi.utils")

local M = {}

local buf = nil
local win = nil
local ns = vim.api.nvim_create_namespace("nimbleapi_explorer")
local source_buf = nil

--- Line-to-route mapping for cursor-based selection.
---@type table<integer, table> 1-indexed line -> route data
local line_map = {}

--- Method icons (nerd font).
local METHOD_ICONS = {
	GET = " ",
	POST = " ",
	PUT = " ",
	PATCH = " ",
	DELETE = " ",
	OPTIONS = " ",
	HEAD = " ",
	TRACE = " ",
	WEBSOCKET = " ",
	API_ROUTE = " ",
}

function M.is_open()
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.get_buf()
	return buf
end

function M.on_buf_wipeout()
	win = nil
	buf = nil
	source_buf = nil
end

function M.explorer()
	if M.is_open() then
		M.close()
		return
	end
	M.open()
end

function M.open()
	local config = require("nimbleapi.config").options
	source_buf = vim.api.nvim_get_current_buf()

	-- Create scratch buffer
	buf = vim.api.nvim_create_buf(false, true)

	-- Open split
	local pos = config.explorer.position == "right" and "botright" or "topleft"
	vim.cmd(pos .. " vsplit")
	vim.cmd("vertical resize " .. config.explorer.width)
	win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	-- Buffer options
	local buf_opts = {
		buftype = "nofile",
		bufhidden = "wipe",
		swapfile = false,
		modifiable = false,
		filetype = "nimbleapi-explorer",
		buflisted = false,
	}
	for k, v in pairs(buf_opts) do
		vim.api.nvim_set_option_value(k, v, { buf = buf })
	end

	-- Window options
	local win_opts = {
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		wrap = false,
		cursorline = true,
		winfixwidth = true,
		spell = false,
		list = false,
	}
	for k, v in pairs(win_opts) do
		vim.api.nvim_set_option_value(k, v, { win = win })
	end

	M.set_keymaps()
	M.render(source_buf)
end

function M.close()
	if win and vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	win = nil
	buf = nil
	source_buf = nil
end

function M.refresh()
	if not M.is_open() then
		return
	end
	require("nimbleapi.cache").invalidate_all()
	M.render(source_buf)
end

function M.set_keymaps()
	if not buf then
		return
	end

	local opts = { buffer = buf, noremap = true, silent = true, nowait = true }

	vim.keymap.set("n", "<CR>", function()
		M.jump_to_route()
	end, opts)

	vim.keymap.set("n", "o", function()
		M.jump_to_route()
	end, opts)

	vim.keymap.set("n", "s", function()
		M.jump_to_route("split")
	end, opts)

	vim.keymap.set("n", "v", function()
		M.jump_to_route("vsplit")
	end, opts)

	vim.keymap.set("n", "r", function()
		M.refresh()
	end, opts)

	vim.keymap.set("n", "t", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		local route = line_map[cursor[1]]
		if route and route.method then
			require("nimbleapi.http").test_route(route)
		end
	end, opts)

	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)
end

function M.jump_to_route(split_cmd)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win)
	local line_nr = cursor[1]
	local route = line_map[line_nr]
	if not route or not route.file then
		return
	end

	-- Switch to previous window
	vim.cmd("wincmd p")

	if split_cmd then
		vim.cmd(split_cmd)
	end

	vim.cmd("edit " .. vim.fn.fnameescape(route.file))
	if route.line then
		vim.api.nvim_win_set_cursor(0, { route.line, 0 })
		vim.cmd("normal! zz")
	end
end

--- Render the route explorer into the sidebar buffer.
---@param context_buf integer|nil
function M.render(context_buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	local config = require("nimbleapi.config").options
	local cache = require("nimbleapi.cache")
	local route_ctx = nil
	if context_buf and vim.api.nvim_buf_is_valid(context_buf) then
		route_ctx = { bufnr = context_buf }
	end
	local all_routes = cache.get_all_routes(route_ctx)

	-- Get current buffer's file path for filtering
	local current_buf = context_buf
	if not current_buf or not vim.api.nvim_buf_is_valid(current_buf) then
		current_buf = vim.api.nvim_get_current_buf()
	end
	local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(current_buf))

	-- Clear previous state
	line_map = {}
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

	local lines = {}
	local highlights = {} -- { line_idx (0-based), col_start, col_end, hl_group }

	if not all_routes or #all_routes == 0 then
		local providers = require("nimbleapi.providers")
		local provider = providers.get_provider(route_ctx)
		local provider_name = provider and provider.name or "unknown"
		lines = {
			" Route Explorer",
			string.rep("─", 38),
			"",
			"  No routes found.",
			provider and ("  Provider: " .. provider_name) or "  No framework detected.",
			"  Run :NimbleAPI info for details",
		}
		table.insert(highlights, { 0, 0, #lines[1], "NimbleApiTitle" })
		table.insert(highlights, { 1, 0, #lines[2], "NimbleApiSeparator" })
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		M._apply_highlights(highlights)
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
		return
	end

	-- Group routes by file
	local file_order = {}
	local groups = {}
	for _, route in ipairs(all_routes) do
		local f = route.file or ""
		if not groups[f] then
			groups[f] = {}
			table.insert(file_order, f)
		end
		table.insert(groups[f], route)
	end

	-- Filter to current file if it has routes, otherwise show all
	local show_files = file_order
	if groups[current_file] then
		show_files = { current_file }
	end

	-- Determine app file (first file in original order) for header
	local providers = require("nimbleapi.providers")
	local provider = providers.get_provider(route_ctx)
	local provider_label = provider and provider.name or "routes"
	local app_file = utils.basename(file_order[1] or "")
	local title = " " .. provider_label .. " (" .. app_file .. ")"
	table.insert(lines, title)
	table.insert(highlights, { 0, 0, #title, "NimbleApiTitle" })
	local sep = string.rep("─", 38)
	table.insert(lines, sep)
	table.insert(highlights, { 1, 0, #sep, "NimbleApiSeparator" })

	-- Sort show_files: main app file first, rest alphabetically
	local main_file = file_order[1]
	table.sort(show_files, function(a, b)
		if a == main_file then return true end
		if b == main_file then return false end
		return a < b
	end)

	for gi, filepath in ipairs(show_files) do
		local file_routes = groups[filepath]
		if file_routes then
			-- File header line
			local header = " " .. utils.basename(filepath)
			local header_line_idx = #lines
			table.insert(lines, header)
			line_map[header_line_idx + 1] = { file = filepath, line = 1 }
			table.insert(highlights, { header_line_idx, 0, #header, "NimbleApiRouter" })

			-- Route lines
			local win_width = (win and vim.api.nvim_win_is_valid(win))
				and vim.api.nvim_win_get_width(win)
				or config.explorer.width
			for _, route in ipairs(file_routes) do
				M._render_route_line(lines, highlights, route, config, win_width)
			end

			-- Blank separator between groups (not after the last one)
			if gi < #show_files then
				table.insert(lines, "")
			end
		end
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	M._apply_highlights(highlights)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	-- Position cursor on the first route line (line 3: after title + sep)
	if win and vim.api.nvim_win_is_valid(win) then
		local first_route_line = 3
		if first_route_line <= #lines then
			pcall(vim.api.nvim_win_set_cursor, win, { first_route_line, 0 })
		end
	end
end

--- Render a single route line (flat, indented, no tree chars).
---@param lines string[]
---@param highlights table[]
---@param route table
---@param config table
---@param win_width integer
function M._render_route_line(lines, highlights, route, config, win_width)
	local line_idx = #lines

	local use_icons = config.explorer.icons
	local method_str = route.method or "???"
	local icon = ""
	if use_icons then
		icon = METHOD_ICONS[method_str] or "  "
	end

	local method_pad = method_str .. string.rep(" ", 9 - #method_str)
	local path = (route.path or "/"):gsub("[\n\r]", "")
	local func_name = ((route.func or "?"):gsub("[\n\r]", "")) .. "()"

	-- Build left part (indent + icon + method + path) and right part (func name)
	local left = "  " .. icon .. method_pad .. path
	local left_len = #left
	local right_len = #func_name
	-- Pad between path and func_name so func_name is right-aligned to window edge
	local gap = win_width - left_len - right_len
	if gap < 2 then
		gap = 2
	end
	local line = left .. string.rep(" ", gap) .. func_name
	table.insert(lines, line)

	-- Store line-to-route mapping (1-indexed)
	line_map[line_idx + 1] = route

	-- Highlights
	local method_start = 2 + #icon
	local method_end = method_start + #method_str
	table.insert(highlights, { line_idx, method_start, method_end, "NimbleApiMethod" .. method_str })

	local path_start = method_start + #method_pad
	local path_end = path_start + #path
	table.insert(highlights, { line_idx, path_start, path_end, "NimbleApiPath" })

	local func_start = left_len + gap
	table.insert(highlights, { line_idx, func_start, func_start + right_len, "NimbleApiFunc" })
end

--- Apply highlight extmarks to the buffer.
---@param highlights table[]
function M._apply_highlights(highlights)
	for _, hl in ipairs(highlights) do
		pcall(vim.api.nvim_buf_set_extmark, buf, ns, hl[1], hl[2], {
			end_col = hl[3],
			hl_group = hl[4],
		})
	end
end

return M
