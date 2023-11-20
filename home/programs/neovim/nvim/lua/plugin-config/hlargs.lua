local ok, hlargs = pcall(require, "hlargs")

if not ok then
	return
end

hlargs.setup()
