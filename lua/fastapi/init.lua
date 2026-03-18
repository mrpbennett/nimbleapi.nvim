local M = {}

---@param opts? table
function M.setup(opts)
  require("fastapi.config").setup(opts)

  -- Load providers (registers them with the provider registry)
  require("fastapi.providers.fastapi")
  require("fastapi.providers.springboot")

  local config = require("fastapi.config").options

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
    vim.api.nvim_set_hl(0, "FastapiMethod" .. method, vim.tbl_extend("keep", { default = true }, hl_opts))
  end
  vim.api.nvim_set_hl(0, "FastapiTitle", { default = true, bold = true, fg = "#e0af68" })
  vim.api.nvim_set_hl(0, "FastapiRouter", { default = true, fg = "#bb9af7", italic = true })
  vim.api.nvim_set_hl(0, "FastapiPath", { default = true, fg = "#a9b1d6" })
  vim.api.nvim_set_hl(0, "FastapiFunc", { default = true, fg = "#7dcfff" })
  vim.api.nvim_set_hl(0, "FastapiTreeGuide", { default = true, fg = "#3b4261" })
  vim.api.nvim_set_hl(0, "FastapiSeparator", { default = true, fg = "#3b4261" })

  -- Legacy single-picker keymap (backwards compat)
  if config.picker.keymap then
    vim.keymap.set("n", config.picker.keymap, function()
      M.pick()
    end, { desc = "FastAPI: route picker" })
  end

  -- <leader>F* keymaps
  local km = config.keymaps or {}
  local binds = {
    { km.toggle,   function() M.toggle() end,   "FastAPI: toggle explorer" },
    { km.pick,     function() M.pick() end,      "FastAPI: route picker" },
    { km.refresh,  function() M.refresh() end,   "FastAPI: refresh routes" },
    { km.codelens, function() M.codelens() end,  "FastAPI: toggle codelens" },
  }
  for _, b in ipairs(binds) do
    if b[1] then
      vim.keymap.set("n", b[1], b[2], { desc = b[3] })
    end
  end
end

function M.toggle()
  require("fastapi.explorer").toggle()
end

function M.pick()
  require("fastapi.picker").pick()
end

function M.refresh()
  require("fastapi.cache").invalidate_all()
  local explorer = require("fastapi.explorer")
  if explorer.is_open() then
    explorer.refresh()
  end
end

function M.codelens()
  local codelens = require("fastapi.codelens")
  local config = require("fastapi.config").options
  config.codelens.enabled = not config.codelens.enabled
  if config.codelens.enabled then
    codelens.attach(vim.api.nvim_get_current_buf())
    vim.notify("FastAPI codelens enabled", vim.log.levels.INFO)
  else
    codelens.detach(vim.api.nvim_get_current_buf())
    vim.notify("FastAPI codelens disabled", vim.log.levels.INFO)
  end
end

--- Get all routes (flat list). Convenience for external consumers.
---@return table[]
function M.get_routes()
  return require("fastapi.cache").get_all_routes()
end

--- Get route tree (hierarchical). Convenience for external consumers.
---@return table|nil
function M.get_route_tree()
  return require("fastapi.cache").get_route_tree()
end

return M
