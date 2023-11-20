local M = {
  dir = "~/.local/share/nvim/nix/hlslens",
  lazy = true,
  keys = { "/", "?" },
  dependencies = { dir = "~/.local/share/nvim/nix/plenary" },
  config = true,
}

return M
