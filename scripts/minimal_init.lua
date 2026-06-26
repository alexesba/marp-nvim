local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":p:h:h")
vim.opt.rtp:prepend(root)

local plenary_path = os.getenv("PLENARY_PATH")
if not plenary_path or plenary_path == "" then
  plenary_path = root .. "/.deps/plenary.nvim"
  if vim.fn.isdirectory(plenary_path) == 0 then
    vim.fn.mkdir(root .. "/.deps", "p")
    local job = vim.fn.jobstart({
      "git",
      "clone",
      "--depth",
      "1",
      "https://github.com/nvim-lua/plenary.nvim",
      plenary_path,
    })
    local result = vim.fn.jobwait({ job }, 120000)
    if result[1] ~= 0 then
      error("failed to clone plenary.nvim into " .. plenary_path)
    end
  end
end

vim.opt.rtp:prepend(plenary_path)
