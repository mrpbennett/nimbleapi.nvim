local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:append(root)

local ok, err = pcall(function()
  require("spec.provider_detection_spec").run()
end)

if ok then
  vim.cmd("cq 0")
else
  vim.api.nvim_err_writeln(err)
  vim.cmd("cq 1")
end
