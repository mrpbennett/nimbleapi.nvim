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

--- Open a picker for FastAPI routes.
--- The backend is determined by `config.options.picker.provider` (explicit) or
--- auto-detected in order: snacks → telescope → builtin.
---@param opts? table  Passed through to the backend picker
function M.pick(opts)
  local config = require("fastapi.config")
  local provider = (config.options.picker or {}).provider or detect_provider()

  local ok, backend = pcall(require, "fastapi.pickers." .. provider)
  if not ok then
    vim.notify(
      "fastapi.nvim: could not load picker backend '" .. provider .. "': " .. backend,
      vim.log.levels.ERROR
    )
    return
  end

  backend.pick(opts)
end

return M
