return {
	dir = "~/.local/share/nvim/nix/treesitter",
	build = ":TSUpdate",
	lazy = true,
	event = "VeryLazy",
	dependencies = {
		{ dir = "~/.local/share/nvim/nix/treesitter-textobjects" },
		{
			dir = "~/.local/share/nvim/nix/hlargs",
			config = true,
			dependencies = {
				dir = "~/.local/share/nvim/nix/treesitter"
			},
		},
		-- { "p00f/nvim-ts-rainbow" },
-- }

		config = function()
			local ts = require("nvim-treesitter.configs")
			ts.setup({
				auto_install = true,
				sync_install = false,
				ensure_installed = {
					"maintained",
				},
				highlight = {
					enable = true,
					additional_vim_regex_highlighting = false,
				},
			})
		end,
	},
}
