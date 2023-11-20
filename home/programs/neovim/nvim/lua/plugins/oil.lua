local M = {
	dir = "~/.local/share/nvim/nix/oil",
	lazy = true,
	keys = { "-" },
}

function M.config()
	require("oil").setup({
		columns = {
			"icon",
		},
		view_options = {
			show_hidden = true,
		},
		keymaps = {
			["g?"] = "actions.show_help",
			["<CR>"] = "actions.select",
			["-"] = "actions.parent",
			["_"] = "actions.open_cwd",
			["`"] = "actions.cd",
			["~"] = "actions.tcd",
			["g."] = "actions.toggle_hidden",
		},
		use_default_keymaps = false,
		skip_confirm_for_simple_edits = true,
	})
	vim.keymap.set("n", "-", require("oil").open, { desc = "Open parent directory" })
end

return M
