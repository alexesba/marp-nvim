local config = require("marp.config")
local util = require("marp.util")

local M = {}

local PROFILE_DIR_NAME = "marp-nvim-preview"

local EDGE_PATHS = {
  "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/mnt/c/Program Files/Microsoft/Edge/Application/msedge.exe",
}

local UNIX_BROWSER_NAMES = {
  "google-chrome-stable",
  "google-chrome",
  "chromium-browser",
  "chromium",
  "microsoft-edge-stable",
  "microsoft-edge",
}

local MAC_BROWSER_PATHS = {
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
}

M._dedicated_open = false

--- Marker string embedded in the --user-data-dir path for process cleanup.
function M.profile_marker()
  return PROFILE_DIR_NAME
end

function M.platform()
  if util.is_wsl() then
    return "wsl"
  end
  if vim.fn.has("mac") == 1 then
    return "mac"
  end
  if vim.fn.has("unix") == 1 then
    return "unix"
  end
  return "other"
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

function M.profile_dir_unix()
  local opts = config.options
  if opts.dedicated_preview_profile and opts.dedicated_preview_profile ~= "" then
    return opts.dedicated_preview_profile
  end

  local tmp = vim.env.TMPDIR or vim.env.TEMP or "/tmp"
  if tmp:sub(-1) == "/" then
    tmp = tmp:sub(1, -2)
  end

  return tmp .. "/" .. PROFILE_DIR_NAME
end

--- Chromium flags for a dedicated preview profile (app mode: no URL bar, single window).
function M.dedicated_launch_flags(profile, url)
  return {
    "--user-data-dir=" .. profile,
    "--no-first-run",
    "--no-default-browser-check",
    "--hide-crash-restore-bubble",
    "--disable-sync",
    "--app=" .. url,
  }
end

--- Backward-compatible alias.
M.dedicated_edge_launch_flags = M.dedicated_launch_flags

local function default_preferences()
  return {
    bookmark_bar = { show_on_all_tabs = false },
    browser = { show_bookmark_bar = false },
    distribution = {
      import_bookmarks = false,
      skip_first_run_ui = true,
    },
    profile = {
      exit_type = "Normal",
      exited_cleanly = true,
    },
  }
end

local function patch_preferences_table(prefs)
  prefs.bookmark_bar = prefs.bookmark_bar or {}
  prefs.bookmark_bar.show_on_all_tabs = false
  prefs.browser = prefs.browser or {}
  prefs.browser.show_bookmark_bar = false
  prefs.distribution = prefs.distribution or {}
  prefs.distribution.import_bookmarks = false
  prefs.distribution.skip_first_run_ui = true
  prefs.profile = prefs.profile or {}
  prefs.profile.exited_cleanly = true
  prefs.profile.exit_type = "Normal"
  return prefs
end

local function write_preferences(path, prefs)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local file = io.open(path, "w")
  if not file then
    return
  end
  file:write(vim.json.encode(prefs))
  file:close()
end

local function prepare_preferences_file(path)
  local file = io.open(path, "r")
  if not file then
    write_preferences(path, default_preferences())
    return
  end

  local content = file:read("*a")
  file:close()

  local ok, prefs = pcall(vim.json.decode, content)
  if ok and type(prefs) == "table" then
    write_preferences(path, patch_preferences_table(prefs))
    return
  end

  content = content:gsub('"exited_cleanly"%s*:%s*false', '"exited_cleanly":true')
  content = content:gsub('"exit_type"%s*:%s*"[^"]*"', '"exit_type":"Normal"')
  content = content:gsub('"show_on_all_tabs"%s*:%s*true', '"show_on_all_tabs":false')
  content = content:gsub('"show_bookmark_bar"%s*:%s*true', '"show_bookmark_bar":false')
  content = content:gsub('"import_bookmarks"%s*:%s*true', '"import_bookmarks":false')

  file = io.open(path, "w")
  if not file then
    return
  end
  file:write(content)
  file:close()
end

local function sanitize_profile_file(path)
  local file = io.open(path, "r")
  if not file then
    return
  end

  local content = file:read("*a")
  file:close()

  content = content:gsub('"exited_cleanly"%s*:%s*false', '"exited_cleanly":true')
  content = content:gsub('"exit_type"%s*:%s*"[^"]*"', '"exit_type":"Normal"')

  file = io.open(path, "w")
  if not file then
    return
  end

  file:write(content)
  file:close()
end

function M.prepare_chromium_profile(profile_dir, separator)
  separator = separator or "/"
  prepare_preferences_file(profile_dir .. separator .. "Default" .. separator .. "Preferences")
  sanitize_profile_file(profile_dir .. separator .. "Local State")
end

--- Backward-compatible alias.
function M.sanitize_chromium_profile(profile_dir, separator)
  M.prepare_chromium_profile(profile_dir, separator)
end

function M.prepare_wsl_profile(profile_win)
  local profile_wsl = M.win_to_wsl(profile_win)
  if profile_wsl then
    M.prepare_chromium_profile(profile_wsl, "/")
    return
  end

  M.sanitize_wsl_profile(profile_win)
end

function M.sanitize_wsl_profile(profile_win)
  local escaped = profile_win:gsub("'", "''")
  local ps = string.format(
    [[$paths = @('%s\Default\Preferences', '%s\Local State'); foreach ($path in $paths) { if (-not (Test-Path -LiteralPath $path)) { continue }; $content = Get-Content -LiteralPath $path -Raw; $content = $content -replace '"exited_cleanly"\s*:\s*false', '"exited_cleanly":true'; $content = $content -replace '"exit_type"\s*:\s*"[^"]*"', '"exit_type":"Normal"'; $content = $content -replace '"show_on_all_tabs"\s*:\s*true', '"show_on_all_tabs":false'; $content = $content -replace '"show_bookmark_bar"\s*:\s*true', '"show_bookmark_bar":false'; $content = $content -replace '"import_bookmarks"\s*:\s*true', '"import_bookmarks":false'; [System.IO.File]::WriteAllText($path, $content) }]],
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

local function resolve_on_path(name)
  local path = vim.fn.exepath(name)
  if path ~= "" then
    return path
  end
  return nil
end

function M.find_chromium_executable()
  local opts = config.options
  if opts.dedicated_browser and opts.dedicated_browser ~= "" then
    if vim.fn.executable(opts.dedicated_browser) == 1 or vim.fn.filereadable(opts.dedicated_browser) == 1 then
      return opts.dedicated_browser
    end
  end

  for _, name in ipairs(UNIX_BROWSER_NAMES) do
    local path = resolve_on_path(name)
    if path then
      return path
    end
  end

  for _, path in ipairs(MAC_BROWSER_PATHS) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

function M.uses_dedicated_preview()
  return config.options.preview_browser == "dedicated"
end

function M.dedicated_supported()
  local platform = M.platform()
  return platform == "wsl" or platform == "mac" or platform == "unix"
end

--- Whether :MarpStop will close a dedicated preview browser instance.
function M.closes_on_stop()
  return M.uses_dedicated_preview() and M.dedicated_supported()
end

local function launch_dedicated(browser, profile, url, prepare_fn)
  M.close_dedicated()
  prepare_fn(profile)

  local argv = vim.list_extend({ browser }, M.dedicated_launch_flags(profile, url))

  local jobid = vim.fn.jobstart(argv, { detach = true })
  if jobid <= 0 then
    return false, "failed to launch dedicated browser"
  end

  M._dedicated_open = true
  return true
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

  return launch_dedicated(edge, profile, url, M.prepare_wsl_profile)
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
    M.prepare_wsl_profile(profile)
  end
end

function M.open_unix_dedicated(url)
  local browser = M.find_chromium_executable()
  if not browser then
    return false, "Chromium-based browser not found (try dedicated_browser)"
  end

  local profile = M.profile_dir_unix()
  return launch_dedicated(browser, profile, url, function(dir)
    M.prepare_chromium_profile(dir, "/")
  end)
end

function M.close_unix_dedicated()
  M._dedicated_open = false

  vim.system({ "pkill", "-f", PROFILE_DIR_NAME }, { text = true }):wait()

  local profile = M.profile_dir_unix()
  if profile then
    M.prepare_chromium_profile(profile, "/")
  end
end

function M.open_dedicated(url)
  local platform = M.platform()
  if platform == "wsl" then
    return M.open_wsl_dedicated(url)
  end
  if platform == "mac" or platform == "unix" then
    return M.open_unix_dedicated(url)
  end
  return false, "dedicated preview is not supported on this platform"
end

function M.close_dedicated()
  local platform = M.platform()
  if platform == "wsl" then
    M.close_wsl_dedicated()
  elseif platform == "mac" or platform == "unix" then
    M.close_unix_dedicated()
  end
end

--- Open the Marp preview in a browser appropriate for the current platform.
function M.open_preview(url)
  if M.uses_dedicated_preview() then
    local ok, err = M.open_dedicated(url)
    if ok then
      return true
    end
    util.log_warn((err or "could not open dedicated browser") .. "; using system browser")
  end

  util.open_url_in_browser(url)
  return true
end

--- Close a dedicated preview browser when preview_browser = "dedicated".
function M.close_preview()
  if M.closes_on_stop() then
    M.close_dedicated()
  end
end

function M.dedicated_open()
  return M._dedicated_open
end

return M
