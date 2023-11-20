local ok, tscontext = pcall(require, "treesitter-context")

if not ok then
	return
end

tscontext.setup({
	-- enable = true, -- Enable this plugin (Can be enabled/disabled later via commands)
	-- max_lines = 0, -- How many lines the window should span. Values <= 0 mean no limit.
	-- trim_scope = "outer", -- Which context lines to discard if `max_lines` is exceeded. Choices: 'inner', 'outer'
	-- patterns = { -- Match patterns for TS nodes. These get wrapped to match at word boundaries.
	--   -- For all filetypes
	--   -- Note that setting an entry here replaces all other patterns for this entry.
	--   -- By setting the 'default' entry below, you can control which nodes you want to
	--   -- appear in the context window.
	--   default = {
	--     "case",
	--     "class",
	--     "for",
	--     "function",
	--     "if",
	--     "method",
	--     "switch",
	--     "while",
	--   },
	--   -- Patterns for specific filetypes
	--   -- If a pattern is missing, *open a PR* so everyone can benefit.
	--   tex = {
	--     "chapter",
	--     "section",
	--     "subsection",
	--     "subsubsection",
	--   },
	--   rust = {
	--     "enum",
	--     "impl_item",
	--     "struct",
	--   },
	--   scala = {
	--     "object_definition",
	--   },
	--   vhdl = {
	--     "architecture_body",
	--     "entity_declaration",
	--     "process_statement",
	--   },
	--   markdown = {
	--     "section",
	--   },
	--   hcl = {
	--     "identifier",
	--   },
	-- },
	-- exact_patterns = {
	--   -- Example for a specific filetype with Lua patterns
	--   -- Treat patterns.rust as a Lua pattern (i.e "^impl_item$" will
	--   -- exactly match "impl_item" only)
	--   -- rust = true,
	-- },
	--
	-- -- [!] The options below are exposed but shouldn't require your attention,
	-- --     you can safely ignore them.
	--
	-- zindex = 20, -- The Z-index of the context window
	-- mode = "cursor", -- Line used to calculate context. Choices: 'cursor', 'topline'
	-- separator = nil, -- Separator between context and content. Should be a single character string, like '-'.
})
