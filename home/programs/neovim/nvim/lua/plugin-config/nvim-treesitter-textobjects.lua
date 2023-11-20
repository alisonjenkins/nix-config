local ok, tsconfigs = pcall(require, "nvim-treesitter.configs")

if not ok then
	return
end

tsconfigs.setup({
	-- textobjects = {
	--   select = {
	--     enable = true,
	--
	--     -- Automatically jump forward to textobj, similar to targets.vim
	--     lookahead = true,
	--
	--     keymaps = {
	--       -- You can use the capture groups defined in textobjects.scm
	--       ["af"] = "@function.outer",
	--       ["if"] = "@function.inner",
	--       ["ac"] = "@class.outer",
	--       -- you can optionally set descriptions to the mappings (used in the desc parameter of nvim_buf_set_keymap
	--       ["ic"] = { query = "@class.inner", desc = "Select inner part of a class region" },
	--     },
	--     -- You can choose the select mode (default is charwise 'v')
	--     selection_modes = {
	--       ["@parameter.outer"] = "v", -- charwise
	--       ["@function.outer"] = "V", -- linewise
	--       ["@class.outer"] = "<c-v>", -- blockwise
	--     },
	--     -- If you set this to `true` (default is `false`) then any textobject is
	--     -- extended to include preceding xor succeeding whitespace. Succeeding
	--     -- whitespace has priority in order to act similarly to eg the built-in
	--     -- `ap`.
	--     include_surrounding_whitespace = true,
	--   },
	-- },
})
