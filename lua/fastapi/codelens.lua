local M = {}

local ns = vim.api.nvim_create_namespace("fastapi_codelens")

--- Extmark ID -> route data mapping.
---@type table<integer, table>
local extmark_data = {}

--- Set of attached buffer numbers.
---@type table<integer, boolean>
local attached_bufs = {}

--- Check if a buffer matches test file patterns.
---@param bufnr integer
---@return boolean
local function is_test_file(bufnr)
  local config = require("fastapi.config").options
  local filepath = vim.api.nvim_buf_get_name(bufnr)
  if filepath == "" then
    return false
  end

  local filename = vim.fn.fnamemodify(filepath, ":t")
  local rel_path = vim.fn.fnamemodify(filepath, ":.")
  local ext = filename:match("%.([^%.]+)$") or ""

  -- Get test patterns: prefer provider-specific, fall back to config
  local providers = require("fastapi.providers")
  local provider = providers.get_provider()
  local test_patterns = (provider and provider.test_patterns) or config.codelens.test_patterns

  for _, pattern in ipairs(test_patterns) do
    -- Convert glob to lua pattern for simple matching
    if pattern:find("**/", 1, true) then
      -- "tests/**/*.py" -> match any file under tests/
      local prefix = pattern:match("^(.-)%*%*/")
      local pat_ext = pattern:match("%.([^%.]+)$") or ""
      if prefix and rel_path:match("^" .. vim.pesc(prefix)) and ext == pat_ext then
        return true
      end
    elseif pattern:find("*", 1, true) then
      -- "test_*.py" -> match filename pattern
      local lua_pat = "^" .. vim.pesc(pattern):gsub("%%%*", ".*") .. "$"
      if filename:match(lua_pat) then
        return true
      end
    else
      if filename == pattern then
        return true
      end
    end
  end

  return false
end

--- Attach codelens to a buffer if it's a test file.
---@param bufnr integer
function M.attach(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if not is_test_file(bufnr) then
    return
  end

  -- Clear previous marks
  M.clear(bufnr)
  attached_bufs[bufnr] = true

  -- Get route lookup table
  local route_lookup = require("fastapi.cache").get_route_lookup()
  if vim.tbl_isempty(route_lookup) then
    return
  end

  -- Extract test client calls from this buffer
  local providers = require("fastapi.providers")
  local provider = providers.get_provider()
  local calls
  if provider then
    calls = provider.extract_test_calls_buf(bufnr)
  else
    calls = require("fastapi.parser").extract_test_calls_buf(bufnr)
  end

  for _, call in ipairs(calls) do
    -- Try to match the test path to a known route
    local matches = M._find_matching_routes(call.path, call.method, route_lookup)
    if #matches > 0 then
      local route = matches[1]
      local rel_file = vim.fn.fnamemodify(route.file, ":t")
      local annotation = route.func .. "()  " .. rel_file .. ":" .. route.line

      local id = vim.api.nvim_buf_set_extmark(bufnr, ns, call.line - 1, 0, {
        virt_text = {
          { "  -> ", "Comment" },
          { annotation, "FastapiFunc" },
        },
        virt_text_pos = "eol",
        hl_mode = "combine",
        priority = 100,
      })

      extmark_data[id] = route
    end
  end

  -- Set up buffer-local keymap for jumping to route definition
  if not vim.b[bufnr].fastapi_codelens_keymap then
    vim.keymap.set("n", "gd", function()
      M.jump_to_route(bufnr)
    end, {
      buffer = bufnr,
      noremap = true,
      silent = true,
      desc = "Jump to FastAPI route definition",
    })
    vim.b[bufnr].fastapi_codelens_keymap = true
  end
end

--- Find routes matching a test path and method.
---@param test_path string
---@param test_method string|nil
---@param route_lookup table
---@return table[]
function M._find_matching_routes(test_path, test_method, route_lookup)
  -- Direct path match
  local direct = route_lookup[test_path]
  if direct then
    if test_method then
      for _, route in ipairs(direct) do
        if route.method == test_method then
          return { route }
        end
      end
    end
    return direct
  end

  -- Try matching with path parameter patterns
  -- e.g., test path "/users/123" should match route "/users/{user_id}"
  for path, routes in pairs(route_lookup) do
    if path:find("{", 1, true) then
      -- Convert route path to a regex-like pattern
      local pattern = "^" .. path:gsub("{[^}]+}", "[^/]+") .. "$"
      if test_path:match(pattern) then
        if test_method then
          for _, route in ipairs(routes) do
            if route.method == test_method then
              return { route }
            end
          end
        end
        return routes
      end
    end
  end

  return {}
end

--- Jump to the route definition at the current cursor position.
---@param bufnr integer
function M.jump_to_route(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { row, 0 }, { row, -1 }, { details = true })
  if #marks > 0 then
    local route = extmark_data[marks[1][1]]
    if route and route.file then
      vim.cmd("edit " .. vim.fn.fnameescape(route.file))
      vim.api.nvim_win_set_cursor(0, { route.line, 0 })
      vim.cmd("normal! zz")
    end
  end
end

--- Clear all codelens extmarks from a buffer.
---@param bufnr integer
function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clean up extmark data for this buffer
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
  for _, mark in ipairs(marks) do
    extmark_data[mark[1]] = nil
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Detach codelens from a buffer.
---@param bufnr integer
function M.detach(bufnr)
  M.clear(bufnr)
  attached_bufs[bufnr] = nil
end

--- Refresh codelens for the current buffer.
function M.refresh_current()
  local bufnr = vim.api.nvim_get_current_buf()
  if attached_bufs[bufnr] then
    M.attach(bufnr)
  end
end

return M
