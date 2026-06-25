local config = require("marp/config")
local install = require("marp.install")
local marp = require("marp/marp")

local M = {}

M.setup = config.setup
M.start = marp.start
M.stop = marp.stop
M.status = marp.status
M.toggle = marp.toggle
M.install = install.sync

-- create MarpStart command
vim.api.nvim_create_user_command("MarpStart", M.start, { desc = "Start Marp" })
vim.api.nvim_create_user_command("MarpStop", M.stop, { desc = "Stop Marp" })
vim.api.nvim_create_user_command("MarpStatus", M.status, { desc = "Show Marp status" })
vim.api.nvim_create_user_command("MarpToggle", M.toggle, { desc = "Toggle Marp (start/stop)" })
vim.api.nvim_create_user_command("MarpInstall", function(opts)
  local ok, err = install.sync(opts.args ~= "" and opts.args or nil)
  if ok then
    vim.notify("Marp CLI is installed", vim.log.levels.INFO)
  else
    vim.notify("Marp install failed: " .. (err or "unknown error"), vim.log.levels.ERROR)
  end
end, { desc = "Install bundled Marp CLI", nargs = "?" })

return M
