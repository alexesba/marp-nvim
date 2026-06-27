local config = require("marp.config")
local util = require("marp.util")

local function norm(path)
  local resolved = path
  if vim.fs and vim.fs.realpath then
    local ok, real = pcall(vim.fs.realpath, path)
    if ok and real then
      resolved = real
    end
  end
  resolved = vim.fn.fnamemodify(resolved, ":p")
  if resolved:sub(-1) == "/" then
    resolved = resolved:sub(1, -2)
  end
  return resolved
end

describe("marp.util", function()
  local root
  local original_cwd

  before_each(function()
    config.setup()
    original_cwd = vim.fn.getcwd()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.cmd("cd " .. vim.fn.fnameescape(root))
  end)

  after_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    pcall(vim.fn.delete, root, "rf")
  end)

  local function write_markdown(path, name)
    local file = path .. "/" .. name
    local f = io.open(file, "w")
    f:write("# slide\n")
    f:close()
    return file
  end

  local function open_markdown_buffer(file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    vim.bo.filetype = "markdown"
  end

  describe("resolve_server_dir", function()
    it("uses server_dir when set", function()
      local slides = root .. "/slides"
      vim.fn.mkdir(slides, "p")

      config.setup({ server_dir = slides })

      assert.equals(norm(slides), norm(util.resolve_server_dir()))
    end)

    it("uses the markdown buffer directory when use_buffer_dir is true", function()
      local slides = vim.fn.getcwd() .. "/slides"
      vim.fn.mkdir(slides, "p")
      local file = write_markdown(slides, "deck.md")

      open_markdown_buffer(file)

      assert.equals(norm(slides), norm(util.resolve_server_dir()))
    end)

    it("falls back to cwd when use_buffer_dir is false", function()
      local slides = vim.fn.getcwd() .. "/slides"
      vim.fn.mkdir(slides, "p")
      local file = write_markdown(slides, "deck.md")

      config.setup({ use_buffer_dir = false })
      open_markdown_buffer(file)

      assert.equals(norm(vim.fn.getcwd()), norm(util.resolve_server_dir()))
    end)

    it("falls back to cwd when the buffer is not markdown", function()
      local slides = vim.fn.getcwd() .. "/slides"
      vim.fn.mkdir(slides, "p")
      local file = write_markdown(slides, "deck.md")

      vim.cmd("edit " .. vim.fn.fnameescape(file))
      vim.bo.filetype = "text"

      assert.equals(norm(vim.fn.getcwd()), norm(util.resolve_server_dir()))
    end)
  end)

  describe("display_server_dir", function()
    it("shows / when server_dir is cwd", function()
      assert.equals("/.", util.display_server_dir(vim.fn.getcwd()))
    end)

    it("shows a relative path for a subdirectory of cwd", function()
      local slides = vim.fn.getcwd() .. "/slides"
      vim.fn.mkdir(slides, "p")

      assert.equals("/slides", util.display_server_dir(slides))
    end)

    it("shows the directory name when outside cwd", function()
      local outside = "/tmp/marp-nvim-spec-outside"
      vim.fn.mkdir(outside, "p")

      assert.equals("/marp-nvim-spec-outside", util.display_server_dir(outside))

      vim.fn.delete(outside, "rf")
    end)
  end)

  describe("dir_contains_md_files", function()
    it("returns true when a markdown file exists", function()
      write_markdown(root, "deck.md")

      assert.is_true(util.dir_contains_md_files(root))
    end)

    it("returns false when no markdown files exist", function()
      local f = io.open(root .. "/readme.txt", "w")
      f:write("nope\n")
      f:close()

      assert.is_false(util.dir_contains_md_files(root))
    end)
  end)

  describe("can_start_server", function()
    it("returns true for a readable markdown buffer", function()
      local file = write_markdown(root, "deck.md")
      open_markdown_buffer(file)

      assert.is_true(util.can_start_server())
    end)

    it("returns true when the resolved directory contains markdown", function()
      write_markdown(root, "deck.md")
      vim.cmd("enew")

      assert.is_true(util.can_start_server())
    end)

    it("returns false when there is no markdown buffer or directory content", function()
      vim.cmd("enew")

      assert.is_false(util.can_start_server())
    end)
  end)

  describe("preview_host", function()
    it("uses preview_host from config when set", function()
      config.setup({ preview_host = "192.168.1.10" })

      assert.equals("192.168.1.10", util.preview_host())
    end)

    it("builds preview URLs with the configured host", function()
      config.setup({ preview_host = "192.168.1.10" })

      assert.equals("http://192.168.1.10:8081/", util.preview_url(8081))
    end)

    it("builds local health-check URLs on 127.0.0.1", function()
      assert.equals("http://127.0.0.1:8080/", util.local_url(8080))
      assert.equals("http://127.0.0.1:8081/close", util.local_url(8081, "/close"))
    end)
  end)
end)
