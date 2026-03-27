local M = {}

---@class NimbleApiExplorerConfig
---@field position "left"|"right"
---@field width integer
---@field icons boolean

---@class NimbleApiPickerConfig
---@field keymap string|false
---@field provider "telescope"|"snacks"|"builtin"|nil  -- nil = auto-detect

---@class NimbleApiKeymapsConfig
---@field explorer string|false
---@field picker string|false
---@field refresh string|false
---@field codelens string|false
---@field test string|false
---@field http_run string|false
---@field http_replay string|false
---@field http_inspect string|false
---@field http_env string|false

---@class NimbleApiCodelensConfig
---@field enabled boolean
---@field test_patterns string[]

---@class NimbleApiWatchConfig
---@field enabled boolean
---@field debounce_ms integer

---@class NimbleApiHttpConfig
---@field base_url string
---@field split "vertical"|"horizontal"|"tab"

---@class NimbleApiConfig
---@field provider string|nil
---@field explorer NimbleApiExplorerConfig
---@field picker NimbleApiPickerConfig
---@field keymaps NimbleApiKeymapsConfig
---@field codelens NimbleApiCodelensConfig
---@field watch NimbleApiWatchConfig
---@field http NimbleApiHttpConfig

---@type NimbleApiConfig
M.defaults = {
	provider = nil, -- auto-detect; override: "fastapi", "spring"
	explorer = {
		position = "right",
		width = 40,
		icons = true,
	},
	picker = {
		keymap = false,
	},
	keymaps = {
		explorer = "<leader>Ne",
		picker = "<leader>Np",
		refresh = "<leader>Nr",
		codelens = "<leader>Nc",
		test = "<leader>Nt",
		-- kulala actions (buffer-local on ft=http)
		http_run = "<leader>Ns",
		http_replay = "<leader>NR",
		http_inspect = "<leader>Ni",
		http_env = "<leader>NE",
	},
	http = {
		base_url = "http://localhost:8000",
		split = "vertical",
	},
	codelens = {
		enabled = true,
		test_patterns = { "test_*.py", "*_test.py", "tests/**/*.py" },
	},
	watch = {
		enabled = true,
		debounce_ms = 200,
	},
}

---@type NimbleApiConfig
M.options = vim.deepcopy(M.defaults)

---@param user_opts? table
function M.setup(user_opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
