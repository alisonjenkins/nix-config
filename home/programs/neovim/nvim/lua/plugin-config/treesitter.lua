local ok, treesitter = pcall(require, "nvim-treesitter.configs")

if not ok then
	return
end

local ignore_plugin = {}

if vim.fn.has("macunix") == 1 then
	table.insert(ignore_plugin, "haskell")
end

local options = {
	ensure_installed = "all",
	ignore_install = ignore_plugin,

	highlight = {
		enable = true,
		use_languagetree = true,
	},
	indent = false,
	rainbow = {
		enable = true,
	},
	autopairs = {
		enable = false,
	},
	autotag = {
		enable = true,
		filetypes = { "html", "xml" },
	},
	context_commentstring = {
		enable = true,
		config = {
			javascriptreact = {
				style_element = "{/*%s*/}",
			},
		},
	},
	textobjects = {
		select = {
			enable = true,

			-- Automatically jump forward to textobj, similar to targets.vim
			lookahead = true,

			keymaps = {
				-- You can use the capture groups defined in textobjects.scm
				["af"] = "@function.outer",
				["if"] = "@function.inner",
				["ac"] = "@class.outer",
				["ic"] = "@class.inner",

				-- Or you can define your own textobjects like this
				["iF"] = {
					python = "(function_definition) @function",
					cpp = "(function_definition) @function",
					c = "(function_definition) @function",
					java = "(method_declaration) @function",
				},
			},
		},
	},
}

treesitter.setup(options)

vim.o.foldmethod = "expr"
vim.wo.foldexpr = "nvim_treesitter#foldexpr()"
