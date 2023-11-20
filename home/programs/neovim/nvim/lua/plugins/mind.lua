local M = {
  "phaazon/mind.nvim",
  branch = "v2.2",
  dependencies = "nvim-lua/plenary.nvim",
  cmd = { "MindOpenMain", "MindOpenProject", "MindOpenSmartProject", "MindReloadState", "MindClose" },
}

function M.config()
  require("mind").setup()
end

return M
