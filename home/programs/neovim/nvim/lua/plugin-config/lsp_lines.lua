local ok, lines = pcall(require, "lsp_lines")
if not ok then
	return
end

lines.setup()

vim.diagnostic.config({
	virtual_text = false,
})
