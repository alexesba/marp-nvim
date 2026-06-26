local config = require("marp.config")

describe("marp.config", function()
  before_each(function()
    package.loaded["marp.config"] = nil
    config = require("marp.config")
  end)

  it("applies defaults on load", function()
    assert.equals(8080, config.options.port)
    assert.equals(30, config.options.wait_for_response_timeout)
    assert.equals(1, config.options.wait_for_response_delay)
    assert.is_nil(config.options.marp_command)
    assert.is_true(config.options.auto_install)
    assert.is_true(config.options.use_npx_fallback)
    assert.equals("latest", config.options.marp_version)
    assert.is_false(config.options.close_browser_on_stop)
    assert.is_nil(config.options.wrapper_port)
    assert.is_nil(config.options.server_dir)
    assert.is_true(config.options.use_buffer_dir)
  end)

  it("merges user options without mutating defaults", function()
    config.setup({
      port = 9000,
      close_browser_on_stop = true,
    })

    assert.equals(9000, config.options.port)
    assert.is_true(config.options.close_browser_on_stop)
    assert.equals(30, config.options.wait_for_response_timeout)

    config.setup()
    assert.equals(8080, config.options.port)
    assert.is_false(config.options.close_browser_on_stop)
  end)

  it("replaces the full options table on each setup", function()
    config.setup({ use_buffer_dir = false })
    assert.is_false(config.options.use_buffer_dir)

    config.setup({ server_dir = "/tmp/slides" })
    assert.equals("/tmp/slides", config.options.server_dir)
    assert.is_true(config.options.use_buffer_dir)
  end)
end)
