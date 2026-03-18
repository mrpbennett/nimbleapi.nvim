local utils = require("fastapi.utils")

local M = {}

M.name = "fastapi"
M.language = "python"
M.file_extensions = { "py" }
M.test_patterns = { "test_*.py", "*_test.py", "tests/**/*.py" }
M.path_param_pattern = "{[^}]+}"

--- Detect if this is a FastAPI project.
---@param root string
---@return boolean
function M.detect(root)
  -- Check pyproject.toml or setup.py for fastapi dependency
  local pyproject = utils.join(root, "pyproject.toml")
  if utils.file_exists(pyproject) then
    if utils.file_contains(pyproject, "fastapi") then
      return true
    end
  end

  local setup_py = utils.join(root, "setup.py")
  if utils.file_exists(setup_py) then
    if utils.file_contains(setup_py, "fastapi") then
      return true
    end
  end

  local requirements = utils.join(root, "requirements.txt")
  if utils.file_exists(requirements) then
    if utils.file_contains(requirements, "fastapi") then
      return true
    end
  end

  -- Fallback: check for .py files containing FastAPI(
  local py_files = utils.glob_files(root, "**/*.py", {
    ".venv", "venv", "__pycache__", "node_modules", ".git",
  })
  for _, f in ipairs(py_files) do
    local rel = utils.relative(f, root)
    if not rel:match("^tests?/") and not rel:match("^test_") then
      if utils.file_contains(f, "FastAPI(") then
        return true
      end
    end
  end

  return false
end

--- Find the FastAPI app entry point.
---@param _root string
---@return table|nil app { file, var_name, line }
function M.find_app(_root)
  return require("fastapi.app_finder").find_app()
end

--- Get all routes as a flat list.
---@param _root string
---@return table[]
function M.get_all_routes(_root)
  local app = require("fastapi.app_finder").find_app()
  if not app then
    return {}
  end

  local router_resolver = require("fastapi.router_resolver")
  local tree = router_resolver.build_route_tree(app)
  if not tree then
    return {}
  end

  return router_resolver.flatten_routes(tree)
end

--- Build the route tree (used by cache for tree-level caching).
---@param _root string
---@return table|nil
function M.get_route_tree(_root)
  local app = require("fastapi.app_finder").find_app()
  if not app then
    return nil
  end
  return require("fastapi.router_resolver").build_route_tree(app)
end

--- Extract routes from a single file.
---@param filepath string
---@return table[]
function M.extract_routes(filepath)
  return require("fastapi.parser").extract_routes(filepath)
end

--- Extract include_router() calls from a file.
---@param filepath string
---@return table[]
function M.extract_includes(filepath)
  return require("fastapi.parser").extract_include_routers(filepath)
end

--- Extract test client calls from a buffer.
---@param bufnr integer
---@return table[]
function M.extract_test_calls_buf(bufnr)
  return require("fastapi.parser").extract_test_calls_buf(bufnr)
end

--- Find project root.
---@return string
function M.find_project_root()
  return require("fastapi.import_resolver").find_project_root()
end

-- Register with the provider registry
require("fastapi.providers").register(M)

return M
