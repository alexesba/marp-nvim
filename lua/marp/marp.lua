local cli = require("marp.cli")
local config = require("marp/config")
local util = require("marp/util")

local M = {}
M.jobid = 0
M._intentional_stop = false

local function on_job_exit(_, exit_code, _)
  M.jobid = 0

  if M._intentional_stop then
    M._intentional_stop = false
    return
  end

  if exit_code ~= 0 then
    util.log_warn("server exited unexpectedly (code=" .. exit_code .. ")")
  end
end

local function marp_running()
  return M.jobid ~= 0
end

--[[
    Toggles the Marp server.
    @usage
    ```lua
    local marp = require("marp")
    marp.toggle()
    ```
]]
function M.toggle()
  if marp_running() then
    M.stop()
  else
    M.start()
  end
end

--[[
    Starts the Marp server.
    @usage
    ```lua
    local marp = require("marp")
    marp.start()
    ```
]]
function M.start()
  if not util.dir_contains_md_files(vim.fn.getcwd()) then
    util.log_info("no Markdown files found, exiting!")
    return
  end

  if marp_running() then
    util.log_info("already running")
    return
  end

  local port = config.options.port
  local wait_for_response_timeout = config.options.wait_for_response_timeout
  local wait_for_response_delay = config.options.wait_for_response_delay

  local argv, env, err = cli.server_argv(port, vim.fn.getcwd())
  if not argv then
    util.log_error(err or "could not resolve Marp CLI")
    return
  end

  util.log_info("starting server on http://localhost:" .. port)

  M.jobid = vim.fn.jobstart(argv, {
    env = env,
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = on_job_exit,
  })

  if M.jobid <= 0 then
    util.log_error("failed to start Marp server")
    return
  end

  if not util.wait_for_response("http://localhost:" .. port, wait_for_response_timeout, wait_for_response_delay) then
    return
  end

  util.open_url_in_browser("http://localhost:" .. port)
end

--[[
    Stops the Marp server.
    @usage
    ```lua
    local marp = require("marp")
    marp.stop()
    ```
]]
function M.stop()
  if M.jobid == 0 then
    util.log_info("not running")
    return
  end

  M._intentional_stop = true
  vim.fn.jobstop(M.jobid)
  M.jobid = 0
  util.log_info("server stopped")
end

--[[
    Logs the status of the Marp server.
    @usage
    ```lua
    local marp = require("marp")
    marp.status()
    ```
]]
function M.status()
  if M.jobid == 0 then
    util.log_info("not running")
  else
    util.log_info("running")
  end
end

return M
