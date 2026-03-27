local M = {}

--- Detect which picker backend to use.
---@return "telescope"|"snacks"|"builtin"
local function detect_provider()
  if pcall(require, "snacks.picker") then
    return "snacks"
  end
  if pcall(require, "telescope") then
    return "telescope"
  end
  return "builtin"
end

--- Open a picker for routes.
--- The backend is determined by `config.options.picker.provider` (explicit) or
--- auto-detected in order: snacks → telescope → builtin.
---@param opts? table  Passed through to the backend picker
function M.picker(opts)
  local config = require("nimbleapi.config")
  local provider = (config.options.picker or {}).provider or detect_provider()

  local ok, backend = pcall(require, "nimbleapi.pickers." .. provider)
  if not ok then
    vim.notify(
      "nimbleapi.nvim: could not load picker backend '" .. provider .. "': " .. backend,
      vim.log.levels.ERROR
    )
    return
  end

  backend.picker(opts)
end

M.pick = M.picker -- backward compat (telescope extension)

return M
