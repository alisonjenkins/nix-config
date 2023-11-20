local M = {
  "iamcco/markdown-preview.nvim",
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  ft = { "markdown" },
}

function M.config()
  vim.g.mkdp_browser = "firefox"
end

return M
