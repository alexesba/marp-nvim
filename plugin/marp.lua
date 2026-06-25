local group = vim.api.nvim_create_augroup("Marp", { clear = true })

local function load()
  require("marp")
end

vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = load,
})

-- Plugin may be added to rtp after the first FileType event (e.g. lazy.nvim).
if vim.bo.filetype == "markdown" then
  load()
end
