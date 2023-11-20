local M = {
  dir = "~/.local/share/nvim/nix/crates",
  event = { "BufRead Cargo.toml" },
  dependencies = {
    { dir = "~/.local/share/nvim/nix/plenary" }
  },
}

function M.config()
  require"crates".setup()
end

return M
