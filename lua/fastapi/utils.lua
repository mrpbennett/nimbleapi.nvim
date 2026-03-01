local M = {}

--- Read a file from disk, returning its contents as a string or nil on failure.
---@param filepath string
---@return string|nil
function M.read_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

--- Check if a file exists and is readable.
---@param filepath string
---@return boolean
function M.file_exists(filepath)
  return vim.fn.filereadable(filepath) == 1
end

--- Check if a directory exists.
---@param dirpath string
---@return boolean
function M.dir_exists(dirpath)
  return vim.fn.isdirectory(dirpath) == 1
end

--- Get the directory portion of a file path.
---@param filepath string
---@return string
function M.dirname(filepath)
  return vim.fn.fnamemodify(filepath, ":h")
end

--- Normalize a path (resolve . and .., remove trailing slashes).
---@param path string
---@return string
function M.normalize(path)
  return vim.fs.normalize(path)
end

--- Join path segments.
---@param ... string
---@return string
function M.join(...)
  local parts = { ... }
  return table.concat(parts, "/")
end

--- Get the filename (tail) of a path.
---@param filepath string
---@return string
function M.basename(filepath)
  return vim.fn.fnamemodify(filepath, ":t")
end

--- Make a path relative to a root directory.
---@param filepath string
---@param root string
---@return string
function M.relative(filepath, root)
  filepath = M.normalize(filepath)
  root = M.normalize(root)
  if not root:match("/$") then
    root = root .. "/"
  end
  if filepath:sub(1, #root) == root then
    return filepath:sub(#root + 1)
  end
  return filepath
end

--- Glob for files, excluding common non-source directories.
---@param pattern string
---@param root string
---@return string[]
function M.glob_py_files(root, pattern)
  pattern = pattern or "**/*.py"
  local exclude_dirs = {
    ".venv",
    "venv",
    "__pycache__",
    "node_modules",
    ".git",
    ".tox",
    ".mypy_cache",
    ".pytest_cache",
    "dist",
    "build",
    "*.egg-info",
  }

  local files = vim.fn.globpath(root, pattern, false, true)
  local filtered = {}
  for _, f in ipairs(files) do
    local rel = M.relative(f, root)
    local skip = false
    for _, exc in ipairs(exclude_dirs) do
      if rel:match("^" .. vim.pesc(exc) .. "/") or rel:match("/" .. vim.pesc(exc) .. "/") then
        skip = true
        break
      end
    end
    if not skip then
      table.insert(filtered, f)
    end
  end
  return filtered
end

--- Simple string-contains check for pre-filtering files.
---@param filepath string
---@param needle string
---@return boolean
function M.file_contains(filepath, needle)
  local content = M.read_file(filepath)
  if not content then
    return false
  end
  return content:find(needle, 1, true) ~= nil
end

return M
