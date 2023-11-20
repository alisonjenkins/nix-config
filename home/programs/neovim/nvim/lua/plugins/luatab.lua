local M = {
  dir = "~/.local/share/nvim/nix/luatab",
  lazy = true,
  event = "TabNew",
  dependencies = { dir = "~/.local/share/nvim/nix/nvim-web-devicons" },
}

function M.config()
  local luatab = require"luatab"

  luatab.setup({})
end

return M
