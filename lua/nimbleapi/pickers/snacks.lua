local M = {}

local method_hl_map = {
	GET = "NimbleApiMethodGET",
	POST = "NimbleApiMethodPOST",
	PUT = "NimbleApiMethodPUT",
	PATCH = "NimbleApiMethodPATCH",
	DELETE = "NimbleApiMethodDELETE",
	OPTIONS = "NimbleApiMethodOPTIONS",
	HEAD = "NimbleApiMethodHEAD",
	TRACE = "NimbleApiMethodTRACE",
	WEBSOCKET = "NimbleApiMethodWEBSOCKET",
}

---@param opts? table
function M.picker(opts)
	local routes = require("nimbleapi.cache").get_all_routes()
	if #routes == 0 then
		vim.notify("nimbleapi.nvim: no routes found", vim.log.levels.INFO)
		return
	end

	local items = {}
	for _, route in ipairs(routes) do
		table.insert(items, {
			text = route.method .. " " .. route.path .. " → " .. (route.func or "") .. "()",
			file = route.file,
			pos = { route.line, 0 },
			route = route,
		})
	end

	local ok, snacks = pcall(require, "snacks")
	if not ok or not snacks or not snacks.picker then
		vim.notify("nimbleapi.nvim: snacks.nvim picker not available", vim.log.levels.ERROR)
		return
	end

	snacks.picker(vim.tbl_extend("force", {
		title = "NimbleAPI Routes",
		items = items,
		format = function(item, _ctx)
			local route = item.route
			local method_hl = method_hl_map[route.method] or "Normal"
			return {
				{ string.format("%-9s", route.method), method_hl },
				{ " " },
				{ string.format("%-40s", route.path), "Normal" },
				{ " " },
				{ (route.func or "") .. "()", "NimbleApiFunc" },
				{ "  " },
				{ vim.fn.fnamemodify(route.file, ":t"), "Comment" },
			}
		end,
		confirm = function(picker, item)
			picker:close()
			if item then
				vim.cmd("edit " .. vim.fn.fnameescape(item.file))
				vim.api.nvim_win_set_cursor(0, item.pos)
				vim.cmd("normal! zz")
			end
		end,
		actions = {
			test = function(picker, item)
				picker:close()
				if item then
					require("nimbleapi.http").test_route(item.route)
				end
			end,
		},
		win = {
			input = {
				keys = {
					["<C-t>"] = { "test", mode = { "n", "i" } },
				},
			},
		},
	}, opts or {}))
end

return M
