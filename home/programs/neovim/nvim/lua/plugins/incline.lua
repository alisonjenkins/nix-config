local M = {
  dir = ".local/share/nvim/nix/incline",
  lazy = true,
  event = "VeryLazy",
}

function M.config()
  require"incline".setup()
end

return M
