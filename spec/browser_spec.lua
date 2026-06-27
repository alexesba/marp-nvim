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

  describe("profile_dir_unix", function()
    it("uses dedicated_preview_profile when set", function()
      config.setup({ dedicated_preview_profile = "/tmp/custom-preview" })
      assert.equals("/tmp/custom-preview", browser.profile_dir_unix())
    end)

    it("defaults to TMPDIR/marp-nvim-preview", function()
      local original = vim.env.TMPDIR
      vim.env.TMPDIR = "/var/tmp"

      assert.equals("/var/tmp/marp-nvim-preview", browser.profile_dir_unix())

      vim.env.TMPDIR = original
    end)
  end)

  describe("closes_on_stop", function()
    it("is false by default", function()
      assert.is_false(browser.closes_on_stop())
    end)

    it("is true when preview_browser is dedicated on a supported platform", function()
      config.setup({ preview_browser = "dedicated" })

      local original_platform = browser.platform
      browser.platform = function()
        return "unix"
      end
      assert.is_true(browser.closes_on_stop())

      browser.platform = function()
        return "other"
      end
      assert.is_false(browser.closes_on_stop())

      browser.platform = original_platform
    end)
  end)

  describe("dedicated_launch_flags", function()
    it("includes flags that suppress session restore UI", function()
      local flags = browser.dedicated_launch_flags("/tmp/marp-nvim-preview")
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
