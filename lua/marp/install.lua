local util = require("marp.util")

local M = {}

local function plugin_root()
  local path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(path, ":h:h:h")
end

function M.root(plugin_dir)
  return plugin_dir or plugin_root()
end

function M.deps_dir(plugin_dir)
  return M.root(plugin_dir) .. "/deps"
end

function M.bundled_path(plugin_dir)
  local bin = M.deps_dir(plugin_dir) .. "/node_modules/.bin/marp"
  if vim.fn.has("win32") == 1 then
    bin = bin .. ".cmd"
  end
  if vim.fn.filereadable(bin) == 1 or vim.fn.executable(bin) == 1 then
    return bin
  end
  return nil
end

function M.installed(plugin_dir)
  return M.bundled_path(plugin_dir) ~= nil
end

local function run_npm_install(deps_dir, plugin_dir)
  if vim.fn.executable("npm") ~= 1 then
    return false, "npm not found; install Node.js v18+ or set marp_command manually"
  end

  util.log_info("installing Marp CLI into plugin dependencies...")

  local result = vim
    .system({ "npm", "install", "--no-fund", "--no-audit" }, { cwd = deps_dir, text = true })
    :wait()

  if result.code ~= 0 then
    local err = (result.stderr or result.stdout or "npm install failed"):gsub("%s+$", "")
    return false, err
  end

  if M.bundled_path(plugin_dir) then
    util.log_info("Marp CLI installed successfully")
    return true
  end

  return false, "npm install finished but marp binary was not found"
end

function M.sync(plugin_dir)
  plugin_dir = M.root(plugin_dir)
  local deps_dir = M.deps_dir(plugin_dir)

  if vim.fn.isdirectory(deps_dir) ~= 1 then
    return false, "deps directory not found at " .. deps_dir
  end

  if M.installed(plugin_dir) then
    return true
  end

  return run_npm_install(deps_dir, plugin_dir)
end

return M
