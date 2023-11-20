return {
  dir = "~/.local/share/nvim/nix/neotest",
  dependencies = {
    dir = "~/.local/share/nvim/nix/neotest-go",
    dir = "~/.local/share/nvim/nix/neotest-python",
    dir = "~/.local/share/nvim/nix/neotest-rust",
    dir = "~/.local/share/nvim/nix/fixcursorhold",
    dir = "~/.local/share/nvim/nix/plenary",
    dir = "~/.local/share/nvim/nix/treesitter",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-go"),
        require("neotest-python"),
        require("neotest-rust"),
      },
    })
  end
}
