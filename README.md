# 🔌 Marp.nvim
A [neovim](https://neovim.io/) plugin for [Marp](https://marp.app/).

## ✨ Features
- start/stop the Marp server
- toggle the Marp server (start/stop)
- see if Marp server is running
- browser window opens when Marp is running and ready
- automatically installs Marp CLI into the plugin when needed
- optionally close the browser preview tab when stopping the server (`close_browser_on_stop`)

## ⚡️ Requirements

- [Node.js](https://nodejs.org/) v18+ and `npm` (for automatic Marp CLI installation and the preview wrapper)
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
      close_browser_on_stop = true,
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
  close_browser_on_stop = false, -- close preview tab on :MarpStop via preview wrapper
  wrapper_port = nil, -- preview wrapper port; defaults to marp port + 1
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

### Close browser tab on stop

Disabled by default. Set `close_browser_on_stop = true` to open Marp through a small wrapper page so `:MarpStop` can signal the browser to close the tab.

```lua
require("marp").setup({
  close_browser_on_stop = true,
})
```

How it works:

1. Marp still runs on `port` (default `8080`)
2. A small Node wrapper serves `http://127.0.0.1:<port+1>/` and **proxies Marp under `/marp/`** on the same origin
3. The wrapper page uses Server-Sent Events (SSE) to receive a `close` event
4. Injected scripts in proxied Marp pages listen for that close signal (via `postMessage`) and close presenter popups
5. `:MarpStop` POSTs to `/close`, which clears the preview and attempts to close the tab

**Note:** `window.close()` is not guaranteed in every browser. If the tab stays open, it will show a short “Marp preview closed. You can close this tab.” message.

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
