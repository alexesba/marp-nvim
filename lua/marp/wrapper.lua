local util = require("marp.util")

local M = {}

M.jobid = 0
M.wrapper_port = nil

local function plugin_root()
  local path = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(path, ":h:h:h")
end

function M.script_path()
  return plugin_root() .. "/wrapper/server.js"
end

function M.port_for(marp_port)
  local opts = require("marp.config").options
  if opts.wrapper_port then
    return opts.wrapper_port
  end
  return marp_port + 1
end

function M.preview_url()
  if not M.wrapper_port then
    return nil
  end
  return "http://127.0.0.1:" .. M.wrapper_port .. "/"
end

function M.running()
  return M.jobid > 0 and M.wrapper_port ~= nil
end

function M.start(marp_port)
  if M.running() then
    return true
  end

  if vim.fn.executable("node") ~= 1 then
    return false, "node is required for the preview wrapper"
  end

  local script = M.script_path()
  if vim.fn.filereadable(script) ~= 1 then
    return false, "preview wrapper not found at " .. script
  end

  local wrapper_port = M.port_for(marp_port)
  M.wrapper_port = wrapper_port

  M.jobid = vim.fn.jobstart({
    "node",
    script,
    tostring(marp_port),
    tostring(wrapper_port),
  }, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = function()
      M.jobid = 0
      M.wrapper_port = nil
    end,
  })

  if M.jobid <= 0 then
    M.wrapper_port = nil
    return false, "failed to start preview wrapper"
  end

  local url = M.preview_url()
  if not util.wait_for_response(url, 10, 0.2) then
    M.stop()
    return false, "preview wrapper did not become ready"
  end

  return true
end

function M.stop()
  if not M.wrapper_port then
    return
  end

  local wrapper_port = M.wrapper_port
  local wrapper_jobid = M.jobid

  vim.system({
    "curl",
    "-s",
    "-X",
    "POST",
    "http://127.0.0.1:" .. wrapper_port .. "/close",
  }, { text = true }):wait()

  M.wrapper_port = nil
  M.jobid = 0

  if wrapper_jobid > 0 then
    vim.defer_fn(function()
      pcall(vim.fn.jobstop, wrapper_jobid)
    end, 200)
  end
end

return M
