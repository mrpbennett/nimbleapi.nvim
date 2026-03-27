local M = {}

local _did_setup = false

--- Ensure setup() has been called at least once (lazy-loading guard).
local function ensure_setup()
	if not _did_setup then
		M.setup()
	end
end

---@param opts? table
function M.setup(opts)
	_did_setup = true
	require("nimbleapi.config").setup(opts)

	-- Load providers (registers them with the provider registry)
	local providers_to_load = { "chi", "echo", "express", "fastapi", "gin", "springboot", "stdlib" }
	for _, name in ipairs(providers_to_load) do
		local ok, err = pcall(require, "nimbleapi.providers." .. name)
		if not ok then
			vim.notify(
				"nimbleapi.nvim: failed to load provider '" .. name .. "': " .. tostring(err),
				vim.log.levels.WARN
			)
		end
	end

	local config = require("nimbleapi.config").options

	-- Define highlight groups
	local method_highlights = {
		GET = { fg = "#9ece6a", bold = true },
		POST = { fg = "#7aa2f7", bold = true },
		PUT = { fg = "#e0af68", bold = true },
		PATCH = { fg = "#ff9e64", bold = true },
		DELETE = { fg = "#f7768e", bold = true },
		OPTIONS = { fg = "#bb9af7", bold = true },
		HEAD = { fg = "#7dcfff", bold = true },
		TRACE = { fg = "#9aa5ce", bold = true },
		WEBSOCKET = { fg = "#73daca", bold = true },
	}
	for method, hl_opts in pairs(method_highlights) do
		vim.api.nvim_set_hl(0, "NimbleApiMethod" .. method, vim.tbl_extend("keep", { default = true }, hl_opts))
	end
	vim.api.nvim_set_hl(0, "NimbleApiTitle", { default = true, bold = true, fg = "#e0af68" })
	vim.api.nvim_set_hl(0, "NimbleApiRouter", { default = true, fg = "#bb9af7", italic = true })
	vim.api.nvim_set_hl(0, "NimbleApiPath", { default = true, fg = "#a9b1d6" })
	vim.api.nvim_set_hl(0, "NimbleApiFunc", { default = true, fg = "#7dcfff" })
	vim.api.nvim_set_hl(0, "NimbleApiTreeGuide", { default = true, fg = "#3b4261" })
	vim.api.nvim_set_hl(0, "NimbleApiSeparator", { default = true, fg = "#3b4261" })

	-- Legacy single-picker keymap (backwards compat)
	if config.picker.keymap then
		vim.keymap.set("n", config.picker.keymap, function()
			M.picker()
		end, { desc = "NimbleAPI: route picker" })
	end

	-- <leader>F* keymaps
	local km = config.keymaps or {}
	local binds = {
		{
			km.explorer,
			function()
				M.explorer()
			end,
			"NimbleAPI: toggle explorer",
		},
		{
			km.picker,
			function()
				M.picker()
			end,
			"NimbleAPI: route picker",
		},
		{
			km.refresh,
			function()
				M.refresh()
			end,
			"NimbleAPI: refresh routes",
		},
		{
			km.codelens,
			function()
				M.codelens()
			end,
			"NimbleAPI: toggle codelens",
		},
		{
			km.test,
			function()
				M.test()
			end,
			"NimbleAPI: test route",
		},
	}
	for _, b in ipairs(binds) do
		if b[1] then
			vim.keymap.set("n", b[1], b[2], { desc = b[3] })
		end
	end

	-- Kulala keymaps (buffer-local on ft=http, only if kulala is installed)
	local kulala_ok = pcall(require, "kulala")
	if kulala_ok then
		local http_binds = {
			{
				km.http_run,
				function()
					require("kulala").run()
				end,
				"Kulala: send request",
			},
			{
				km.http_replay,
				function()
					require("kulala").replay()
				end,
				"Kulala: replay last request",
			},
			{
				km.http_inspect,
				function()
					require("kulala").inspect()
				end,
				"Kulala: inspect request",
			},
			{
				km.http_env,
				function()
					require("kulala").set_selected_env()
				end,
				"Kulala: set environment",
			},
		}

		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("NimbleApiKulala", { clear = true }),
			pattern = "http",
			callback = function(ev)
				for _, b in ipairs(http_binds) do
					if b[1] then
						vim.keymap.set("n", b[1], b[2], { buffer = ev.buf, desc = b[3] })
					end
				end
			end,
		})
	end
end

function M.explorer()
	ensure_setup()
	require("nimbleapi.explorer").explorer()
end

function M.picker()
	ensure_setup()
	require("nimbleapi.picker").picker()
end

function M.refresh()
	ensure_setup()
	require("nimbleapi.cache").invalidate_all()
	local explorer = require("nimbleapi.explorer")
	if explorer.is_open() then
		explorer.refresh()
	end
end

function M.codelens()
	ensure_setup()
	local codelens = require("nimbleapi.codelens")
	local config = require("nimbleapi.config").options
	config.codelens.enabled = not config.codelens.enabled
	if config.codelens.enabled then
		codelens.attach(vim.api.nvim_get_current_buf())
		vim.notify("NimbleAPI codelens enabled", vim.log.levels.INFO)
	else
		codelens.detach(vim.api.nvim_get_current_buf())
		vim.notify("NimbleAPI codelens disabled", vim.log.levels.INFO)
	end
end

function M.test()
	ensure_setup()
	local cache = require("nimbleapi.cache")
	local routes = cache.get_all_routes()
	if not routes or #routes == 0 then
		vim.notify("NimbleAPI: no routes found — run :NimbleAPI refresh", vim.log.levels.WARN)
		return
	end

	-- Try to resolve route from current cursor position
	local current_file = vim.fs.normalize(vim.api.nvim_buf_get_name(0))
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local best_match = nil
	for _, route in ipairs(routes) do
		if vim.fs.normalize(route.file or "") == current_file then
			if route.line and route.line <= current_line then
				if not best_match or route.line > best_match.line then
					best_match = route
				end
			end
		end
	end

	if best_match then
		require("nimbleapi.http").test_route(best_match)
	else
		-- Fall back to picker
		vim.ui.select(routes, {
			prompt = "Select route to test:",
			format_item = function(route)
				return route.method .. " " .. route.path .. " → " .. (route.func or "") .. "()"
			end,
		}, function(route)
			if route then
				require("nimbleapi.http").test_route(route)
			end
		end)
	end
end

function M.info(ctx)
	ensure_setup()
	local lines = require("nimbleapi.providers").info(ctx)
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

--- Get all routes (flat list). Convenience for external consumers.
---@param ctx string|table|nil
---@return table[]
function M.get_routes(ctx)
	return require("nimbleapi.cache").get_all_routes(ctx)
end

--- Get route tree (hierarchical). Convenience for external consumers.
---@param ctx string|table|nil
---@return table|nil
function M.get_route_tree(ctx)
	return require("nimbleapi.cache").get_route_tree(ctx)
end

return M
