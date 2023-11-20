local M = {
  dir = "~/.local/share/nvim/nix/alpha-nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  priority = 1001,
}

function M.config()
  require"alpha".setup(require("alpha.themes.startify").opts)
end

return M
