local M = {
	dir = "~/.local/share/nvim/nix/indent-blankline",
	lazy = true,
	event = "BufRead",
	main = "ibl",
	opts = {},
}

function M.config()
	require("ibl").setup()
	vim.opt.list = true
	vim.opt.listchars:append("eol:↴")
end

return M
