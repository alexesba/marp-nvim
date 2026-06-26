local config = require("marp.config")

local M = {}

--- Apply lazy.nvim `opts` when the plugin spec has no `config` function.
function M.apply()
  if vim.g.marp_lazy_opts_applied then
    return
  end

  local ok, lazy_config = pcall(require, "lazy.core.config")
  if not ok then
    return
  end

  for _, plugin in pairs(lazy_config.spec.plugins) do
    local is_marp = plugin.name == "marp-nvim"
      or (type(plugin.dir) == "string" and plugin.dir:find("marp%-nvim", 1, true))

    if is_marp and type(plugin.opts) == "table" and next(plugin.opts) ~= nil then
      config.setup(plugin.opts)
      vim.g.marp_lazy_opts_applied = true
      return
    end
  end
end

return M
