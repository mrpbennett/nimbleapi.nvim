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
  local providers_to_load = { "fastapi", "springboot" }
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
      M.pick()
    end, { desc = "NimbleAPI: route picker" })
  end

  -- <leader>F* keymaps
  local km = config.keymaps or {}
  local binds = {
    { km.toggle,   function() M.toggle() end,   "NimbleAPI: toggle explorer" },
    { km.pick,     function() M.pick() end,      "NimbleAPI: route picker" },
    { km.refresh,  function() M.refresh() end,   "NimbleAPI: refresh routes" },
    { km.codelens, function() M.codelens() end,  "NimbleAPI: toggle codelens" },
  }
  for _, b in ipairs(binds) do
    if b[1] then
      vim.keymap.set("n", b[1], b[2], { desc = b[3] })
    end
  end
end

function M.toggle()
  ensure_setup()
  require("nimbleapi.explorer").toggle()
end

function M.pick()
  ensure_setup()
  require("nimbleapi.picker").pick()
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
