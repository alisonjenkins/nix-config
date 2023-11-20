local M = {
	dir = "~/.local/share/nvim/nix/jdtls",
	ft = { "java" },
}

function M.config()
	local home_dir = os.getenv("HOME")
	local project_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":p:h:t")
	local workspace_dir = home_dir .. "/.cache/jdtls-workspaces/" .. project_name

	require("jdtls").start_or_attach({
		cmd = {
			"rtx",
			"exec",
			"java@corretto-17.0.6.10.1",
			"--",
			"java",
			"-Declipse.application=org.eclipse.jdt.ls.core.id1",
			"-Dosgi.bundles.defaultStartLevel=4",
			"-Declipse.product=org.eclipse.jdt.ls.core.product",
			"-Dlog.protocol=true",
			"-Dlog.level=ALL",
			"-Xms1g",
			"--add-modules=ALL-SYSTEM",
			"--add-opens",
			"java.base/java.util=ALL-UNNAMED",
			"--add-opens",
			"java.base/java.lang=ALL-UNNAMED",
			"-jar",
			home_dir
				.. "/.local/share/nvim/mason/packages/jdtls/plugins/org.eclipse.equinox.launcher_1.6.400.v20210924-0641.jar",
			"-configuration",
			home_dir .. "/.local/share/nvim/mason/packages/jdtls/config_linux",
			"-data",
			workspace_dir,
		},
		root_dir = vim.fs.dirname(vim.fs.find({ ".gradlew", ".git", "mvnw" }, { upward = true })[1]),
		on_attach = function(client, bufnr)
			-- With `hotcodereplace = 'auto' the debug adapter will try to apply code changes
			-- you make during a debug session immediately.
			-- Remove the option if you do not want that.
			-- You can use the `JdtHotcodeReplace` command to trigger it manually
			require("jdtls").setup_dap({ hotcodereplace = "auto" })
		end,
	})
end

return M
