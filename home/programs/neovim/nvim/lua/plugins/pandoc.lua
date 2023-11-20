local M = {
  dir = "~/.local/share/nvim/nix/pandoc",
  lazy = true,
  dependencies = {
    dir = "~/.local/share/nvim/nix/plenary",
    dir = "~/.local/share/nvim/nix/nabla", -- Optional. See Extra Features
  },
}

function M.config()
  require"pandoc".setup()
end

return M
