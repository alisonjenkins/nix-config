return {
	dir = "luckasRanarison/nvim-devdocs",
	dependencies = {
		dir = "~/.local/share/nvim/nix/plenary",
		dir = "~/.local/share/nvim/nix/telescope",
		dir = "~/.local/share/nvim/nix/treesitter",
	},
	opts = {},
	config = function()
		require("nvim-devdocs").setup({
			ensure_installed = {
				"ansible",
				"bash",
				"rust",
				"terraform",
			},
		})
	end,
}
