return {
  dir = "~/.local/share/nvim/nix/split-navigator",
  name = "split-navigator",
  config = function()
    require('Navigator').setup()
  end,
}
