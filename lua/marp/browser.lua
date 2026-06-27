local config = require("marp.config")
local util = require("marp.util")

local M = {}

local PROFILE_DIR_NAME = "marp-nvim-preview"

local EDGE_PATHS = {
  "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe",
}

M._dedicated_open = false

--- Marker string embedded in the Edge --user-data-dir path for process cleanup.
function M.profile_marker()
  return PROFILE_DIR_NAME
end

--- Convert a Windows path (C:\foo) to a WSL /mnt/c/foo path.
function M.win_to_wsl(path)
  path = path:gsub("\r", ""):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if path == "" then
    return nil
  end

  local drive, rest = path:match("^(%a):(.*)$")
  if not drive then
    return nil
  end

  rest = rest:gsub("\\", "/")
  if rest:sub(1, 1) ~= "/" then
    rest = "/" .. rest
  end

  return "/mnt/" .. drive:lower() .. rest
end

function M.windows_temp_dir()
  local result = vim.system({ "cmd.exe", "/c", "echo", "%TEMP%" }, { text = true }):wait()
  if result.code ~= 0 or not result.stdout then
    return nil
  end

  local temp = result.stdout:gsub("\r", ""):gsub("\n", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if temp == "" or temp:match("%%") then
    return nil
  end

  return temp
end

function M.profile_dir_win()
  local opts = config.options
  if opts.wsl_preview_profile and opts.wsl_preview_profile ~= "" then
    return opts.wsl_preview_profile
  end

  local temp = M.windows_temp_dir()
  if not temp then
    return nil
  end

  local sep = temp:sub(-1) == "\\" and "" or "\\"
  return temp .. sep .. PROFILE_DIR_NAME
end

--- Chromium flags for a dedicated preview profile (Edge on WSL).
function M.dedicated_edge_launch_flags(profile)
  return {
    "--user-data-dir=" .. profile,
    "--no-first-run",
    "--no-default-browser-check",
    "--hide-crash-restore-bubble",
    "--new-window",
  }
end

--- Clear crash-restore state after force-closing the dedicated profile.
function M.sanitize_wsl_profile(profile_win)
  local escaped = profile_win:gsub("'", "''")
  local ps = string.format(
    [[$paths = @('%s\Default\Preferences', '%s\Local State'); foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path)) { continue }; $content = Get-Content -LiteralPath $path -Raw; $content = $content -replace '"exited_cleanly"\s*:\s*false', '"exited_cleanly":true'; $content = $content -replace '"exit_type"\s*:\s*"[^"]*"', '"exit_type":"Normal"'; [System.IO.File]::WriteAllText($path, $content) }]],
    escaped,
    escaped
  )

  vim.system({
    "powershell.exe",
    "-NoProfile",
    "-Command",
    ps,
  }, { text = true }):wait()
end

function M.find_edge_executable()
  local opts = config.options
  if opts.wsl_browser and opts.wsl_browser ~= "" then
    if vim.fn.filereadable(opts.wsl_browser) == 1 then
      return opts.wsl_browser
    end
  end

  for _, path in ipairs(EDGE_PATHS) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

function M.uses_dedicated_preview()
  return config.options.preview_browser == "dedicated"
end

--- Whether :MarpStop will close a dedicated preview browser instance.
function M.closes_on_stop()
  return M.uses_dedicated_preview() and util.is_wsl()
end

function M.open_wsl_dedicated(url)
  local edge = M.find_edge_executable()
  if not edge then
    return false, "Microsoft Edge not found on Windows"
  end

  local profile = M.profile_dir_win()
  if not profile then
    return false, "could not resolve Windows TEMP directory"
  end

  M.close_wsl_dedicated()
  M.sanitize_wsl_profile(profile)

  local argv = vim.list_extend({ edge }, M.dedicated_edge_launch_flags(profile))
  table.insert(argv, url)

  local jobid = vim.fn.jobstart(argv, { detach = true })

  if jobid <= 0 then
    return false, "failed to launch Microsoft Edge"
  end

  M._dedicated_open = true
  return true
end

function M.close_wsl_dedicated()
  M._dedicated_open = false

  local ps = string.format(
    [[Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object { $_.CommandLine -like '*%s*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }]],
    PROFILE_DIR_NAME
  )

  vim.system({
    "powershell.exe",
    "-NoProfile",
    "-Command",
    ps,
  }, { text = true }):wait()

  local profile = M.profile_dir_win()
  if profile then
    M.sanitize_wsl_profile(profile)
  end
end

--- Open the Marp preview in a browser appropriate for the current platform.
function M.open_preview(url)
  if M.uses_dedicated_preview() then
    if util.is_wsl() then
      local ok, err = M.open_wsl_dedicated(url)
      if ok then
        return true
      end
      util.log_warn((err or "could not open dedicated Edge") .. "; using system browser")
    else
      util.log_info('preview_browser = "dedicated" is only supported on WSL; using system browser')
    end
  end

  util.open_url_in_browser(url)
  return true
end

--- Close a dedicated preview browser when supported (WSL + preview_browser = "dedicated").
function M.close_preview()
  if M.closes_on_stop() then
    M.close_wsl_dedicated()
  end
end

function M.dedicated_open()
  return M._dedicated_open
end

return M
