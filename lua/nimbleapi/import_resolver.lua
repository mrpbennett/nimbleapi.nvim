local utils = require("nimbleapi.utils")

local M = {}

--- Find the project root by walking up from a file path or cwd.
---@param startpath string|nil
---@return string
function M.find_project_root(startpath)
  local markers = { "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt", ".git" }
  return utils.find_project_root(startpath, markers)
end

--- Reset the cached project root (for testing or workspace changes).
function M.reset_root()
  return
end

--- Check if the project uses a src layout.
---@param root string
---@return string|nil src_dir The src directory if it exists, nil otherwise
function M.try_src_layout(root)
  local src = utils.join(root, "src")
  if utils.dir_exists(src) then
    return src
  end
  return nil
end

--- Try to resolve a dotted module path to a filesystem path.
---@param base string Base directory to resolve from
---@param dotted_path string|nil Dotted module path (e.g., "app.routers.users")
---@return string|nil filepath
local function resolve_module_to_file(base, dotted_path)
  if not dotted_path then
    -- Bare relative import, the base itself is the module
    if utils.file_exists(base .. "/__init__.py") then
      return base .. "/__init__.py"
    end
    return nil
  end

  local rel = dotted_path:gsub("%.", "/")
  local full = utils.join(base, rel)

  -- Check as a .py file
  if utils.file_exists(full .. ".py") then
    return full .. ".py"
  end

  -- Check as a package directory
  if utils.file_exists(full .. "/__init__.py") then
    return full .. "/__init__.py"
  end

  return nil
end

--- Resolve a parsed import entry to a file path.
---@param importing_file string Absolute path of the file containing the import
---@param import_info table Parsed import info { module, name, is_relative, level, is_plain_import }
---@param project_root string|nil Override project root
---@return string|nil resolved_file
function M.resolve_import(importing_file, import_info, project_root)
  project_root = project_root or M.find_project_root()

  local base
  if import_info.is_relative then
    base = utils.dirname(importing_file)
    for _ = 1, (import_info.level or 1) - 1 do
      base = utils.dirname(base)
    end
  else
    base = project_root
  end

  -- For plain imports (import X.Y.Z), the module path IS the full dotted path
  if import_info.is_plain_import then
    return resolve_module_to_file(base, import_info.module)
  end

  -- Build the module directory from the module portion
  local module_dir = base
  if import_info.module then
    local rel = import_info.module:gsub("%.", "/")
    module_dir = utils.join(base, rel)
  end

  -- The imported name might be a submodule (file) or a symbol in the module
  local name = import_info.name

  -- Try: name is a submodule file
  local as_file = utils.join(module_dir, name .. ".py")
  if utils.file_exists(as_file) then
    return as_file
  end

  -- Try: name is a subpackage
  local as_pkg = utils.join(module_dir, name, "__init__.py")
  if utils.file_exists(as_pkg) then
    return as_pkg
  end

  -- Name is a symbol inside the module itself
  -- Try module_dir as a .py file
  if utils.file_exists(module_dir .. ".py") then
    return module_dir .. ".py"
  end

  -- Try module_dir as a package
  if utils.file_exists(module_dir .. "/__init__.py") then
    return module_dir .. "/__init__.py"
  end

  -- For absolute imports, try src-layout fallback
  if not import_info.is_relative then
    local src = M.try_src_layout(project_root)
    if src then
      local src_module_dir = src
      if import_info.module then
        src_module_dir = utils.join(src, import_info.module:gsub("%.", "/"))
      end

      local src_file = utils.join(src_module_dir, name .. ".py")
      if utils.file_exists(src_file) then
        return src_file
      end
      local src_pkg = utils.join(src_module_dir, name, "__init__.py")
      if utils.file_exists(src_pkg) then
        return src_pkg
      end
      if utils.file_exists(src_module_dir .. ".py") then
        return src_module_dir .. ".py"
      end
      if utils.file_exists(src_module_dir .. "/__init__.py") then
        return src_module_dir .. "/__init__.py"
      end
    end
  end

  return nil
end

--- Resolve which local name an include_router reference maps to in the import table.
---@param router_ref table { type = "attribute"|"identifier", object?, attr?, name? }
---@param import_table table Maps local_name -> import_info
---@return table|nil import_info The matched import entry
function M.resolve_router_ref(router_ref, import_table)
  if router_ref.type == "identifier" then
    -- Direct variable: include_router(router_var)
    return import_table[router_ref.name]
  elseif router_ref.type == "attribute" then
    -- Attribute access: include_router(module.router)
    -- Look up the object name in imports
    return import_table[router_ref.object]
  end
  return nil
end

return M
