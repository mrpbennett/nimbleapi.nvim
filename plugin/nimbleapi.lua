if vim.g.loaded_nimbleapi then
	return
end
vim.g.loaded_nimbleapi = true

local subcommands = {
	explorer = function()
		require("nimbleapi").explorer()
	end,
	picker = function()
		require("nimbleapi").picker()
	end,
	refresh = function()
		require("nimbleapi").refresh()
	end,
	codelens = function()
		require("nimbleapi").codelens()
	end,
	info = function()
		require("nimbleapi").info()
	end,
	test = function()
		require("nimbleapi").test()
	end,
}

vim.api.nvim_create_user_command("NimbleAPI", function(args)
	local subcmd = args.fargs[1]
	local fn = subcommands[subcmd]
	if fn then
		fn()
	else
		vim.notify("NimbleAPI: unknown subcommand '" .. (subcmd or "") .. "'", vim.log.levels.ERROR)
	end
end, {
	nargs = 1,
	complete = function(lead)
		return vim.tbl_filter(function(key)
			return key:find(lead, 1, true) == 1
		end, vim.tbl_keys(subcommands))
	end,
	desc = "NimbleAPI route explorer",
})

local group = vim.api.nvim_create_augroup("NimbleApiNvim", { clear = true })

-- Debounce timer for file watching
local debounce_timer = nil

vim.api.nvim_create_autocmd("BufWritePost", {
	group = group,
	pattern = { "*.go", "*.java", "*.js", "*.py", "*.ts" },
	callback = function(ev)
		local config = package.loaded["nimbleapi.config"]
		if not config or not config.options.watch or not config.options.watch.enabled then
			return
		end

		-- Only process files the active provider handles
		local providers = package.loaded["nimbleapi.providers"]
		if providers and not providers.handles_file(ev.file, { bufnr = ev.buf, filepath = ev.file }) then
			return
		end

		local cache = package.loaded["nimbleapi.cache"]
		if cache then
			cache.invalidate(ev.file)
		end

		local explorer = package.loaded["nimbleapi.explorer"]
		local codelens = package.loaded["nimbleapi.codelens"]
		local should_refresh = (explorer and explorer.is_open()) or (codelens and config.options.codelens.enabled)

		if not should_refresh then
			return
		end

		local delay = config.options.watch.debounce_ms or 200
		if debounce_timer then
			debounce_timer:stop()
		end
		debounce_timer = vim.defer_fn(function()
			if explorer and explorer.is_open() then
				require("nimbleapi").refresh()
			end
			if codelens and config.options.codelens.enabled then
				codelens.refresh_current()
			end
			debounce_timer = nil
		end, delay)
	end,
	desc = "Refresh routes on source file save",
})

-- Attach codelens when entering test files
vim.api.nvim_create_autocmd("BufEnter", {
	group = group,
	pattern = { "*.go", "*.java", "*.js", "*.py", "*.ts" },
	callback = function(ev)
		local config = package.loaded["nimbleapi.config"]
		if not config or not config.options.codelens or not config.options.codelens.enabled then
			return
		end

		-- Only process files the active provider handles
		local filepath = vim.api.nvim_buf_get_name(ev.buf)
		local providers = package.loaded["nimbleapi.providers"]
		if
			providers
			and filepath ~= ""
			and not providers.handles_file(filepath, { bufnr = ev.buf, filepath = filepath })
		then
			return
		end

		vim.schedule(function()
			local codelens = package.loaded["nimbleapi.codelens"]
			if codelens then
				codelens.attach(ev.buf)
			end
		end)
	end,
	desc = "Attach codelens in test files",
})

-- Cleanup sidebar state on buffer wipeout
vim.api.nvim_create_autocmd("BufWipeout", {
	group = group,
	callback = function(ev)
		local explorer = package.loaded["nimbleapi.explorer"]
		if explorer and ev.buf == explorer.get_buf() then
			explorer.on_buf_wipeout()
		end
	end,
})
