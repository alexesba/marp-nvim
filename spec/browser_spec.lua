local browser = require("marp.browser")
local config = require("marp.config")

describe("marp.browser", function()
  before_each(function()
    config.setup()
    browser._dedicated_open = false
  end)

  describe("win_to_wsl", function()
    it("converts a Windows path to a WSL mount path", function()
      assert.equals("/mnt/c/Users/alice/AppData/Local/Temp", browser.win_to_wsl("C:\\Users\\alice\\AppData\\Local\\Temp"))
    end)

    it("trims CR/LF from cmd.exe output", function()
      assert.equals("/mnt/c/Temp", browser.win_to_wsl("C:\\Temp\r\n"))
    end)

    it("returns nil for invalid paths", function()
      assert.is_nil(browser.win_to_wsl(""))
      assert.is_nil(browser.win_to_wsl("/not/windows"))
    end)
  end)

  describe("uses_dedicated_preview", function()
    it("is false by default", function()
      assert.is_false(browser.uses_dedicated_preview())
    end)

    it("is true when preview_browser is dedicated", function()
      config.setup({ preview_browser = "dedicated" })
      assert.is_true(browser.uses_dedicated_preview())
    end)
  end)

  describe("closes_on_stop", function()
    it("is false by default", function()
      assert.is_false(browser.closes_on_stop())
    end)

    it("requires preview_browser dedicated and WSL", function()
      config.setup({ preview_browser = "dedicated" })

      local original_is_wsl = require("marp.util").is_wsl
      local util = require("marp.util")

      util.is_wsl = function()
        return false
      end
      assert.is_false(browser.closes_on_stop())

      util.is_wsl = function()
        return true
      end
      assert.is_true(browser.closes_on_stop())

      util.is_wsl = original_is_wsl
    end)
  end)

  describe("dedicated_edge_launch_flags", function()
    it("includes flags that suppress session restore UI", function()
      local flags = browser.dedicated_edge_launch_flags("C:\\Temp\\marp-nvim-preview")
      local joined = table.concat(flags, " ")

      assert.matches("marp%-nvim%-preview", joined)
      assert.matches("hide%-crash%-restore%-bubble", joined)
      assert.matches("no%-first%-run", joined)
    end)
  end)

  describe("profile_marker", function()
    it("returns a stable marker for process cleanup", function()
      assert.equals("marp-nvim-preview", browser.profile_marker())
    end)
  end)
end)
