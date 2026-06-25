# 🔌 Marp.nvim
A [neovim](https://neovim.io/) plugin for [Marp](https://marp.app/).

## ✨ Features
- start/stop the Marp server
- toggle the Marp server (start/stop)
- see if Marp server is running
- browser window opens when Marp is running and ready
- automatically installs Marp CLI into the plugin when needed

## ⚡️ Requirements

- [Node.js](https://nodejs.org/) v18+ and `npm` (for automatic Marp CLI installation)
- Alternatively, install [Marp CLI](https://marp.app/) globally and the plugin will use it from your `PATH`

## 📦 Installation

Install the plugin with your preferred package manager:

Packer:
```lua
  use({
    "mpas/marp-nvim",
    ft = "markdown",
    run = function()
      require("marp").install()
    end,
  }),
```

Lazy (recommended — loads on Markdown buffers, installs Marp CLI on plugin install/update):
```lua
  {
    "mpas/marp-nvim",
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
    "mpas/marp-nvim",
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
  close_browser_on_stop = false, -- experimental: close preview tab on :MarpStop
  wrapper_port = nil, -- preview wrapper port; defaults to marp port + 1
}
```

### Experimental: close browser tab on stop

On branch `feature/browser-close-wrapper`, you can enable a small preview wrapper that opens Marp inside a controlled page and listens for a close signal when you run `:MarpStop` (similar in spirit to `markdown-preview.nvim`).

```lua
require("marp").setup({
  close_browser_on_stop = true,
})
```

How it works:

1. Marp still runs on `port` (default `8080`)
2. A tiny Node wrapper serves `http://127.0.0.1:<port+1>/` with an iframe to Marp
3. The wrapper page uses Server-Sent Events (SSE) to receive a `close` event
4. `:MarpStop` POSTs to `/close`, which tells the page to call `window.close()`

**Caveats:** `window.close()` is not guaranteed in every browser — some only allow it for script-opened windows. If the tab stays open, it will show a connection error after the server stops. Requires Node.js (already needed for bundled Marp CLI install).

Marp CLI resolution order when `marp_command` is not set:

1. `marp` on your `PATH`
2. Bundled install in the plugin's `deps/` directory
3. Auto-install into `deps/` if `auto_install` is true
4. `npx @marp-team/marp-cli@<marp_version>` if `use_npx_fallback` is true

In the above example, the Marp server will be started on port 8080, and the plugin will wait for up to 30 seconds for a response from the server before giving up. It will try to connect to the server every second.

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

This plugin is inspired by [aca/marp.nvim](https://github.com/aca/marp.nvim)!
