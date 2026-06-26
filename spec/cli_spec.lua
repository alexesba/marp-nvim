local config = require("marp.config")
local cli = require("marp.cli")

describe("marp.cli", function()
  before_each(function()
    config.setup()
  end)

  describe("resolve_argv", function()
    it("uses marp_command when set", function()
      config.setup({ marp_command = "/custom/marp", auto_install = false, use_npx_fallback = false })

      local argv, err = cli.resolve_argv()

      assert.is_nil(err)
      assert.same({ "/custom/marp" }, argv)
    end)

    it("splits marp_command on whitespace", function()
      config.setup({ marp_command = "npx @marp-team/marp-cli", auto_install = false, use_npx_fallback = false })

      local argv, err = cli.resolve_argv()

      assert.is_nil(err)
      assert.same({ "npx", "@marp-team/marp-cli" }, argv)
    end)
  end)

  describe("server_argv", function()
    it("builds server argv and PORT env from marp_command", function()
      config.setup({ marp_command = "/custom/marp", auto_install = false, use_npx_fallback = false })

      local argv, env, err = cli.server_argv(9090, "/tmp/slides")

      assert.is_nil(err)
      assert.same({ "/custom/marp", "--server", "/tmp/slides" }, argv)
      assert.equals("9090", env.PORT)
    end)
  end)
end)
