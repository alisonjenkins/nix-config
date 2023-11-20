local M = {
  dir = "~/.local/share/nvim/nix/fzf",
  lazy = true,
  build = function()
    vim.fn["fzf#install"]()
  end,
}

return M
