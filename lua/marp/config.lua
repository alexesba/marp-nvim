local M = {}

local defaults = {
  port = 8080, -- the port on which the Marp server should listen
  wait_for_response_timeout = 30, -- how long to wait for a response from the server before giving up
  wait_for_response_delay = 1, -- how long to wait between attempts to connect to the server
  marp_command = nil, -- override Marp executable; nil auto-resolves PATH, bundled, then npx
  auto_install = true, -- install @marp-team/marp-cli into plugin deps when missing
  use_npx_fallback = true, -- use npx when marp is not on PATH and bundled install is unavailable
  marp_version = "latest", -- npx package version when falling back to npx
  close_browser_on_stop = false, -- close preview tab on :MarpStop via preview wrapper
  wrapper_port = nil, -- preview wrapper port; defaults to marp port + 1
  server_dir = nil, -- directory passed to marp --server; nil uses resolve_server_dir()
  use_buffer_dir = true, -- serve the current Markdown buffer's directory instead of cwd
}

M.options = {}

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", {}, defaults, options or {})
end

M.setup()

return M
