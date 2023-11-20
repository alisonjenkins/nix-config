local M = {
	"nvim-tree/nvim-tree.lua",
}

function M.config()
	require("nvim-tree").setup({
		sort_by = "case_sensitive",
		renderer = {
			group_empty = true,
		},
		filters = {
			dotfiles = true,
		},
	})
end

return M
