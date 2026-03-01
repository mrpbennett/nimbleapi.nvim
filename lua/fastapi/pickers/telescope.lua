local M = {}

---@param opts? table Telescope opts
function M.pick(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  opts = opts or require("telescope.themes").get_dropdown({})

  local routes = require("fastapi.cache").get_all_routes()
  if #routes == 0 then
    vim.notify("fastapi.nvim: no routes found", vim.log.levels.INFO)
    return
  end

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 9 },        -- method
      { width = 40 },       -- path
      { remaining = true }, -- function
    },
  })

  local method_hl_map = {
    GET = "FastapiMethodGET",
    POST = "FastapiMethodPOST",
    PUT = "FastapiMethodPUT",
    PATCH = "FastapiMethodPATCH",
    DELETE = "FastapiMethodDELETE",
    OPTIONS = "FastapiMethodOPTIONS",
    HEAD = "FastapiMethodHEAD",
    TRACE = "FastapiMethodTRACE",
    WEBSOCKET = "FastapiMethodWEBSOCKET",
  }

  pickers
    .new(opts, {
      prompt_title = "FastAPI Routes",
      finder = finders.new_table({
        results = routes,
        entry_maker = function(entry)
          local method_hl = method_hl_map[entry.method] or "Normal"

          return {
            value = entry,
            ordinal = entry.method .. " " .. entry.path .. " " .. (entry.func or ""),
            path = entry.file,
            lnum = entry.line,
            display = function()
              return displayer({
                { entry.method, method_hl },
                { entry.path },
                { entry.func .. "()", "FastapiFunc" },
              })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = conf.grep_previewer(opts),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
            vim.cmd("normal! zz")
          end
        end)
        return true
      end,
    })
    :find()
end

return M
