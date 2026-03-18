local utils = require("nimbleapi.utils")
local parser = require("nimbleapi.parser")
local import_resolver = require("nimbleapi.import_resolver")

local M = {}

--- Parse "module.path:var_name" format into components.
---@param entry_point string e.g., "app.main:app"
---@param root string
---@return string|nil filepath, string|nil var_name
local function parse_entry_point(entry_point, root)
  local module_path, var = entry_point:match("^(.+):(.+)$")
  if not module_path then
    return nil, nil
  end

  local rel = module_path:gsub("%.", "/")

  -- Try direct file
  local filepath = utils.join(root, rel .. ".py")
  if utils.file_exists(filepath) then
    return filepath, var
  end

  -- Try package init
  filepath = utils.join(root, rel, "__init__.py")
  if utils.file_exists(filepath) then
    return filepath, var
  end

  -- Try src-layout
  local src = import_resolver.try_src_layout(root)
  if src then
    filepath = utils.join(src, rel .. ".py")
    if utils.file_exists(filepath) then
      return filepath, var
    end
    filepath = utils.join(src, rel, "__init__.py")
    if utils.file_exists(filepath) then
      return filepath, var
    end
  end

  return nil, nil
end

--- Try to read entry point from pyproject.toml [tool.fastapi] section.
---@param root string
---@return string|nil entry_point
local function read_pyproject_entry(root)
  local pyproject = utils.join(root, "pyproject.toml")
  if not utils.file_exists(pyproject) then
    return nil
  end

  local content = utils.read_file(pyproject)
  if not content then
    return nil
  end

  -- Simple pattern-based extraction (avoids TOML parser dependency)
  -- Look for [tool.fastapi] section with app = "module:var"
  local in_section = false
  for line in content:gmatch("[^\r\n]+") do
    if line:match("^%[tool%.fastapi%]") then
      in_section = true
    elseif line:match("^%[") then
      in_section = false
    elseif in_section then
      local app = line:match('^%s*app%s*=%s*"([^"]+)"')
      if app then
        return app
      end
    end
  end

  return nil
end

--- Heuristic scan: find files containing FastAPI() instantiation.
---@param root string
---@return table|nil app { file, var_name, line }
local function heuristic_scan(root)
  -- Get all Python files, excluding test directories and venvs
  local py_files = utils.glob_py_files(root)

  -- Pre-filter: only parse files that contain "FastAPI("
  local candidates = {}
  for _, f in ipairs(py_files) do
    local rel = utils.relative(f, root)
    -- Skip test files
    if not rel:match("^tests?/") and not rel:match("^test_") then
      if utils.file_contains(f, "FastAPI(") then
        table.insert(candidates, f)
      end
    end
  end

  if #candidates == 0 then
    return nil
  end

  -- Sort by path depth (shallower = more likely to be the main app)
  table.sort(candidates, function(a, b)
    local depth_a = select(2, a:gsub("/", ""))
    local depth_b = select(2, b:gsub("/", ""))
    if depth_a ~= depth_b then
      return depth_a < depth_b
    end
    return a < b
  end)

  -- Parse each candidate and return the first one with a FastAPI() assignment
  for _, filepath in ipairs(candidates) do
    local apps = parser.extract_fastapi_apps(filepath)
    if #apps > 0 then
      return apps[1]
    end
  end

  return nil
end

--- Discover the FastAPI app entry point.
--- Two-tier strategy:
--- 1. pyproject.toml [tool.fastapi] section
--- 2. Heuristic scan of all Python files
---@param root string|nil
---@return table|nil app { file, var_name, line }
function M.find_app(root)
  root = root or import_resolver.find_project_root()

  -- Tier 1: pyproject.toml
  local pyproject_entry = read_pyproject_entry(root)
  if pyproject_entry then
    local filepath, var_name = parse_entry_point(pyproject_entry, root)
    if filepath then
      -- Verify it actually contains FastAPI()
      local apps = parser.extract_fastapi_apps(filepath)
      for _, app in ipairs(apps) do
        if app.var_name == var_name then
          return app
        end
      end
      -- Even if var_name doesn't match, use the first app found
      if #apps > 0 then
        return apps[1]
      end
    end
  end

  -- Tier 2: Heuristic scan
  return heuristic_scan(root)
end

return M
