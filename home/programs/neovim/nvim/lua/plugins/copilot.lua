return {
  dir = "~/.local/share/nvim/nix/copilot-lua",
  cmd = "Copilot",
  event = "InsertEnter",
  config = function()
    require("copilot").setup({
      suggestion = {
        auto_trigger = true,
        keymap = {
          accept = "<M-k>"
        }
      },
    })
  end,
}
