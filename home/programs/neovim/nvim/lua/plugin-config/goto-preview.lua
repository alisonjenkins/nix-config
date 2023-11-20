local ok, preview = pcall(require, "goto-preview")
if not ok then
	return
end
preview.setup({
	default_mappings = true,
})
