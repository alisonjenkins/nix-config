local M = {
  dir = "~/.local/share/nvim/nix/comment",
  lazy = false,
  config = function()
    require"Comment".setup()
  end,
}

return M
