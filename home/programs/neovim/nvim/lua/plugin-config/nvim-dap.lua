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
		env = function()
			local variables = {}
			for k, v in pairs(vim.fn.environ()) do
				table.insert(variables, string.format("%s=%s", k, v))
			end
			return variables
		end,
		program = function()
			return vim.fn.input("Path to executable: ", vim.fn.getcwd() .. "/", "file")
		end,
		cwd = "${workspaceFolder}",
		stopOnEntry = true,
	},
}
