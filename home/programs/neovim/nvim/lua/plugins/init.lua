-- vim: set foldmethod=marker foldlevel=0:
return {
	-- Language servers + LSP tools {{{
	{
		dir = "~/.local/share/nvim/nix/dap",
		lazy = true,
		config = function()
			local dap = require("dap")
			local port = 32562

			local code_lldb_extension_path = vim.env.HOME .. "/.local/share/nvim/mason/packages/codelldb/"
			local codelldb_path = code_lldb_extension_path .. "extension/adapter/codelldb"
			-- local liblldb_path = code_lldb_extension_path .. "extension/lldb/lib/liblldb.so"

			dap.adapters.codelldb = {
				type = "server",
				port = port,
				executable = {
					command = codelldb_path,
					args = { "--port", port },
					-- On windows you may have to uncomment this:
					-- detached = false,
				},
			}

			dap.configurations.rust = {
				{
					name = "Launch file",
					type = "codelldb",
					request = "launch",
					program = function()
						return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
					end,
					cwd = "${workspaceFolder}",
					stopOnEntry = true,
				},
			}
		end,
	},
}
