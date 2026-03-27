local M = {}

---@param opts? table Telescope opts
function M.picker(opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  opts = opts or require("telescope.themes").get_dropdown({})

  local routes = require("nimbleapi.cache").get_all_routes()
  if #routes == 0 then
    vim.notify("nimbleapi.nvim: no routes found", vim.log.levels.INFO)
    return
  end

  local displayer = entry_display.create({
    separator = " ",
    items = {
      { width = 9 },        -- method
      { width = 40 },       -- path
      { width = 30 },       -- function
      { remaining = true }, -- filename
    },
  })

  local method_hl_map = {
    GET = "NimbleApiMethodGET",
    POST = "NimbleApiMethodPOST",
    PUT = "NimbleApiMethodPUT",
    PATCH = "NimbleApiMethodPATCH",
    DELETE = "NimbleApiMethodDELETE",
    OPTIONS = "NimbleApiMethodOPTIONS",
    HEAD = "NimbleApiMethodHEAD",
    TRACE = "NimbleApiMethodTRACE",
    WEBSOCKET = "NimbleApiMethodWEBSOCKET",
  }

  pickers
    .new(opts, {
      prompt_title = "NimbleAPI Routes",
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
                { (entry.func or "?") .. "()", "NimbleApiFunc" },
                { vim.fn.fnamemodify(entry.file, ":t"), "Comment" },
              })
            end,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = conf.grep_previewer(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. vim.fn.fnameescape(selection.path))
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
            vim.cmd("normal! zz")
          end
        end)

        local function test_route()
          local selection = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selection then
            require("nimbleapi.http").test_route(selection.value)
          end
        end

        map("i", "<C-t>", test_route)
        map("n", "t", test_route)

        return true
      end,
    })
    :find()
end

return M
