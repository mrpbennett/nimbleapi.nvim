local M = {}

--- Check if kulala.nvim is available.
---@return { available: boolean, message: string|nil }
function M.check_kulala()
  local ok = pcall(require, "kulala")
  if ok then
    return { available = true }
  end
  return { available = false, message = "kulala.nvim is not installed — buffer will open but cannot execute requests" }
end

--- Generate an .http template string for the given route.
---@param route { method: string, path: string, func: string|nil, file: string|nil, line: integer|nil }
---@param opts? { base_url: string|nil }
---@return string
function M.generate_template(route, opts)
  opts = opts or {}
  local base_url = opts.base_url or "http://localhost:8000"
  local method = (route.method or "GET"):upper()

  -- Convert path params: {param} -> {{param}}
  local path = route.path:gsub("{(%w+)}", "{{%1}}")

  -- Extract path params for variable declarations
  local params = {}
  for param in route.path:gmatch("{(%w+)}") do
    table.insert(params, param)
  end

  local lines = {}

  -- Variable declarations for path params
  for _, param in ipairs(params) do
    table.insert(lines, "@" .. param .. " = 1")
  end
  if #params > 0 then
    table.insert(lines, "")
  end

  -- Request name
  table.insert(lines, "# @name " .. (route.func or "request"))

  -- Request line
  table.insert(lines, method .. " {{base_url}}" .. path)

  -- Headers
  table.insert(lines, "Accept: application/json")

  local has_body = method == "POST" or method == "PUT" or method == "PATCH"
  if has_body then
    table.insert(lines, "Content-Type: application/json")
  end

  -- Body scaffold
  if has_body then
    table.insert(lines, "")
    table.insert(lines, "{")
    table.insert(lines, '  ""')
    table.insert(lines, "}")
  end

  table.insert(lines, "")
  return table.concat(lines, "\n")
end

--- Open a scratch buffer with the given .http template.
---@param template string
---@param route { method: string, path: string, func: string|nil }
function M.open_http_buffer(template, route)
  local config = require("nimbleapi.config").options
  local split_type = config.http and config.http.split or "vertical"

  -- Create scratch buffer
  local http_buf = vim.api.nvim_create_buf(false, true)
  if http_buf == 0 then
    vim.notify("NimbleAPI: failed to create HTTP buffer", vim.log.levels.ERROR)
    return
  end

  -- Set buffer lines
  local lines = vim.split(template, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(http_buf, 0, -1, false, lines)

  -- Set buffer name
  local buf_name = "nimbleapi://" .. (route.method or "GET"):upper() .. " " .. (route.path or "/")
  pcall(vim.api.nvim_buf_set_name, http_buf, buf_name)

  -- Open in split
  if split_type == "tab" then
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, http_buf)
  elseif split_type == "horizontal" then
    vim.cmd("split")
    vim.api.nvim_win_set_buf(0, http_buf)
  else
    vim.cmd("vsplit")
    vim.api.nvim_win_set_buf(0, http_buf)
  end

  -- Buffer options
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = http_buf })
  vim.api.nvim_set_option_value("filetype", "http", { buf = http_buf })
  vim.api.nvim_set_option_value("buflisted", false, { buf = http_buf })
  vim.api.nvim_set_option_value("swapfile", false, { buf = http_buf })

  -- Position cursor on the request line (line after @name comment)
  -- Find the line with the HTTP method
  for i, line in ipairs(lines) do
    if line:match("^%u+ ") then
      pcall(vim.api.nvim_win_set_cursor, 0, { i, 0 })
      break
    end
  end
end

--- Public entry point: generate and open an .http buffer for the given route.
---@param route { method: string, path: string, func: string|nil, file: string|nil, line: integer|nil }
function M.test_route(route)
  -- Check kulala availability (warn but continue)
  local kulala_status = M.check_kulala()
  if not kulala_status.available then
    vim.notify("NimbleAPI: " .. kulala_status.message, vim.log.levels.WARN)
  end

  local config = require("nimbleapi.config").options
  local base_url = config.http and config.http.base_url or "http://localhost:8000"

  local template = M.generate_template(route, { base_url = base_url })
  M.open_http_buffer(template, route)
end

return M
