local M = {
  dir = "~/.local/share/nvim/nix/markdown-preview",
  build = function()
    vim.fn["mkdp#util#install"]()
  end,
  ft = { "markdown" },
}

function M.config()
  vim.g.mkdp_browser = "firefox"
end

return M
