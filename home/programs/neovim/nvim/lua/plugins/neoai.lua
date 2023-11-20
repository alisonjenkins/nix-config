return {
  dir = "~/.local/share/nvim/nix/neoai",
  dependencies = {
    dir = "~/.local/share/nvim/nix/nui",
  },
  cmd = {
    "NeoAI",
    "NeoAIOpen",
    "NeoAIClose",
    "NeoAIToggle",
    "NeoAIContext",
    "NeoAIContextOpen",
    "NeoAIContextClose",
    "NeoAIInject",
    "NeoAIInjectCode",
    "NeoAIInjectContext",
    "NeoAIInjectContextCode",
  },
  keys = {
    { "<leader>as", desc = "Summarize Text" },
    { "<leader>ag", desc = "Generate Git Message" },
  },
  config = function()
    require("neoai").setup({
      -- Options go here
    })
  end,
}
