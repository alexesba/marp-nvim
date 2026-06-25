local config = require("marp.config")
local install = require("marp.install")
local util = require("marp.util")

local M = {}

--- Whether a Marp executable is available without npx or auto-install.
function M.has_executable()
  local opts = config.options

  if opts.marp_command and opts.marp_command ~= "" then
    return true
  end

  if vim.fn.executable("marp") == 1 then
    return true
  end

  if install.bundled_path() then
    return true
  end

  return false
end

function M.needs_install()
  return not M.has_executable()
end

local function npx_argv(version)
  return { "npx", "@marp-team/marp-cli@" .. version }
end

---@return string[]|nil argv Prefix argv for `marp --server <dir>` (without --server or directory).
---@return string|nil err
function M.resolve_argv()
  local opts = config.options

  if opts.marp_command then
    if opts.marp_command:match("%s") then
      return vim.split(opts.marp_command, "%s+"), nil
    end
    return { opts.marp_command }, nil
  end

  if vim.fn.executable("marp") == 1 then
    return { "marp" }, nil
  end

  local bundled = install.bundled_path()
  if bundled then
    return { bundled }, nil
  end

  if opts.auto_install then
    local ok, err = install.sync()
    if ok then
      bundled = install.bundled_path()
      if bundled then
        return { bundled }, nil
      end
    elseif err then
      util.log_warn(err)
    end
  end

  if opts.use_npx_fallback then
    if vim.fn.executable("npx") ~= 1 then
      return nil, "Marp CLI not found; install Node.js v18+ or set marp_command"
    end
    local version = opts.marp_version or "latest"
    return npx_argv(version), nil
  end

  return nil, "Marp CLI not found; run :MarpInstall or set marp_command"
end

---@return string[]|nil argv Full argv for starting the Marp server.
---@return table|nil env Environment variables for jobstart.
---@return string|nil err
function M.server_argv(port, cwd)
  local prefix, err = M.resolve_argv()
  if not prefix then
    return nil, nil, err
  end

  local argv = vim.list_extend(vim.deepcopy(prefix), { "--server", cwd })
  return argv, { PORT = tostring(port) }, nil
end

return M
