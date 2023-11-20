return {
	dir = "~/.local/share/nvim/nix/tailwindcss-colorizer-cmp",
	-- optionally, override the default options:
	config = function()
		require("tailwindcss-colorizer-cmp").setup({
			color_square_width = 2,
		})
	end,
}
