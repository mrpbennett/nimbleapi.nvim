local M = {}

---@class FastapiExplorerConfig
---@field position "left"|"right"
---@field width integer
---@field icons boolean

---@class FastapiPickerConfig
---@field keymap string|false
---@field provider "telescope"|"snacks"|"builtin"|nil  -- nil = auto-detect

---@class FastapiKeymapsConfig
---@field toggle string|false
---@field pick string|false
---@field refresh string|false
---@field codelens string|false

---@class FastapiCodelensConfig
---@field enabled boolean
---@field test_patterns string[]

---@class FastapiWatchConfig
---@field enabled boolean
---@field debounce_ms integer

---@class FastapiConfig
---@field provider string|nil
---@field entry_point string|nil
---@field explorer FastapiExplorerConfig
---@field picker FastapiPickerConfig
---@field keymaps FastapiKeymapsConfig
---@field codelens FastapiCodelensConfig
---@field watch FastapiWatchConfig

---@type FastapiConfig
M.defaults = {
  provider = nil, -- auto-detect; override: "fastapi", "spring"
  entry_point = nil, -- auto-detect; override: "app.main:app"
  explorer = {
    position = "left",
    width = 40,
    icons = true,
  },
  picker = {
    keymap = false,
  },
  keymaps = {
    toggle   = "<leader>Ft",
    pick     = "<leader>Fp",
    refresh  = "<leader>Fr",
    codelens = "<leader>Fc",
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

---@type FastapiConfig
M.options = {}

---@param user_opts? table
function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
