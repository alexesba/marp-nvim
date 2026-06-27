# 🔌 Marp.nvim
A [neovim](https://neovim.io/) plugin for [Marp](https://marp.app/).

## ✨ Features
- start/stop the Marp server
- toggle the Marp server (start/stop)
- see if Marp server is running
- browser window opens when Marp is running and ready
- automatically installs Marp CLI into the plugin when needed
- opens the preview in your system browser, or optionally in a dedicated WSL Edge window (`preview_browser`)

## ⚡️ Requirements

- [Node.js](https://nodejs.org/) v18+ and `npm` (for automatic Marp CLI installation)
- Alternatively, install [Marp CLI](https://marp.app/) globally and the plugin will use it from your `PATH`

## 📦 Installation

Install the plugin with your preferred package manager:

Packer:
```lua
  use({
    "alexesba/marp-nvim",
    ft = "markdown",
    run = function()
      require("marp").install()
    end,
  }),
```

Lazy (recommended — loads on Markdown buffers, installs Marp CLI on plugin install/update):
```lua
  {
    "alexesba/marp-nvim",
    ft = "markdown",
    cmd = { "MarpStart", "MarpStop", "MarpToggle", "MarpStatus" },
    build = function(plugin)
      require("marp").install(plugin.dir)
    end,
    config = true,
  },
```

With a specific configuration:
```lua
  {
    "alexesba/marp-nvim",
    ft = "markdown",
    cmd = { "MarpStart", "MarpStop", "MarpToggle", "MarpStatus" },
    build = function(plugin)
      require("marp").install(plugin.dir)
    end,
    config = function()
      require("marp").setup({
        port = 8080,
        wait_for_response_timeout = 30,
        wait_for_response_delay = 1,
      })
    end,
  },
```

With lazy.nvim `opts` (no separate `config` function needed):

```lua
  {
    "alexesba/marp-nvim",
    ft = "markdown",
    cmd = { "MarpStart", "MarpStop", "MarpToggle", "MarpStatus" },
    opts = {
      preview_browser = "dedicated",
    },
    build = function(plugin)
      require("marp").install(plugin.dir)
    end,
  },
```

The plugin also registers a `FileType` autocmd for `markdown`, so it loads when you open a Markdown file even without lazy-loading configuration. With lazy.nvim, `ft = "markdown"` is still recommended so the plugin is not loaded at startup.

If Marp CLI is not found on your `PATH` and is not yet installed in the plugin, `:MarpInstall` is registered automatically so you can install it manually.

## ⚙️ Configuration

The following defaults are provided:

```lua
{
  port = 8080, -- the port on which the Marp server should listen
  wait_for_response_timeout = 30, -- how long to wait for a response from the server before giving up
  wait_for_response_delay = 1, -- how long to wait between attempts to connect to the server
  marp_command = nil, -- override Marp executable; nil auto-resolves PATH, bundled, then npx
  auto_install = true, -- install @marp-team/marp-cli into plugin deps when missing
  use_npx_fallback = true, -- use npx when marp is not on PATH and bundled install is unavailable
  marp_version = "latest", -- npx package version when falling back to npx
  preview_browser = "system", -- "system" | "dedicated" (dedicated closes on :MarpStop on WSL)
  wsl_browser = nil, -- path to msedge.exe on Windows; nil auto-detects under /mnt/c
  wsl_preview_profile = nil, -- Windows --user-data-dir; nil uses %TEMP%/marp-nvim-preview
  preview_host = nil, -- browser preview hostname; nil auto-detects (WSL uses the VM IP)
  server_dir = nil, -- directory passed to marp --server; nil uses resolve_server_dir()
  use_buffer_dir = true, -- serve the current Markdown buffer's directory instead of cwd
}
```

Marp CLI resolution order when `marp_command` is not set:

1. `marp` on your `PATH`
2. Bundled install in the plugin's `deps/` directory
3. Auto-install into `deps/` if `auto_install` is true
4. `npx @marp-team/marp-cli@<marp_version>` if `use_npx_fallback` is true

### Server directory in large projects

By default, `:MarpStart` runs `marp --server` on the **current Markdown buffer's directory**, not Neovim's working directory. This avoids serving an entire repository (for example a Rails app root with `node_modules/`, `tmp/`, and thousands of files).

Override when needed:

```lua
require("marp").setup({
  server_dir = "/path/to/slides", -- always serve this directory
  use_buffer_dir = false,         -- use vim.fn.getcwd() instead of the buffer path
})
```

### Preview browser

Two modes:

| `preview_browser` | `:MarpStart` | `:MarpStop` |
|---|---|---|
| `"system"` (default) | Opens in your OS default browser | Stops Marp only; the tab stays open |
| `"dedicated"` | WSL: opens Microsoft Edge in a temp profile | Stops Marp and closes that Edge window |

**System** (default) matches Marp CLI: simple tab open, no cleanup on stop.

**Dedicated** is for WSL users who want the preview window to disappear on `:MarpStop` without a wrapper or `window.close()` hacks.

```lua
require("marp").setup({
  preview_browser = "dedicated",
})
```

On **macOS and Linux**, `preview_browser = "dedicated"` falls back to the system browser (close on stop is not supported there yet).

How dedicated mode works on WSL:

1. Marp runs on `port` (default `8080`)
2. Edge opens with `--user-data-dir=%TEMP%\marp-nvim-preview` so it does not touch your normal browser session
3. The preview URL uses the WSL VM IP (see below) so Windows can reach the server
4. `:MarpStop` kills only Edge processes using that profile (presenter popups included)

The dedicated profile is sanitized after each stop so Edge does not show a "Restore pages" prompt on the next preview.

Optional overrides:

```lua
require("marp").setup({
  preview_browser = "dedicated",
  wsl_browser = "/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  wsl_preview_profile = "C:\\Users\\you\\AppData\\Local\\Temp\\marp-nvim-preview",
})
```

### WSL (Windows)

Neovim in WSL opens the preview in your **Windows** browser. `127.0.0.1` in WSL is not reachable from Windows, so the plugin uses the WSL VM IP for preview URLs.

On WSL the plugin automatically:

1. Opens the browser using the WSL VM IP (from `hostname -I`)
2. With `preview_browser = "dedicated"`, launches a dedicated Edge window instead of `wslview`

If auto-detection fails, set the host manually:

```lua
require("marp").setup({
  preview_host = "172.21.17.252", -- output of: hostname -I | awk '{print $1}'
})
```

## ⌨️ Keybindings
This plugin does not set any keybindings by default. You can set them yourself like this:

```lua
vim.keymap.set("n", "<leader>MT", "<cmd>MarpToggle<cr>", { noremap = true, silent = true })
vim.keymap.set("n", "<leader>MS", "<cmd>MarpStatus<cr>", { noremap = true, silent = true })
...
```

The following commands are available:
- `:MarpStart` - start the Marp server
- `:MarpStop` - stop the Marp server
- `:MarpToggle` - toggle the Marp server (start/stop)
- `:MarpStatus` - see if Marp server is running
- `:MarpInstall` - install the bundled Marp CLI (only registered when Marp is not already available)

## 🎨 Theming
Marp CLI can recognize custom themes that are in the `themes/` directory in your project's root directory. For example, if you open neovim in the `presentations` directory, created a directory inside of `presentations` called `themes` and place the theme CSS files inside of this directory. They should be automatically loaded by Marp and applied to presentations with the theme specified.

## 💡Inspiration

This plugin is inspired by [aca/marp.nvim](https://github.com/aca/marp.nvim) and [mpas/marp-nvim](https://github.com/mpas/marp-nvim)!
