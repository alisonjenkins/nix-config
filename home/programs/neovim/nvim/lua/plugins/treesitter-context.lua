return {
	dir = "~/.local/share/nvim/nix/nvim-treesitter-context",
	lazy = true,
	event = "VeryLazy",
	config = true,
	dependencies = { dir = ".local/share/nvim/nix/treesitter" },
}
