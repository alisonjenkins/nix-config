local M = {
  "pwntester/octo.nvim",
  lazy = true,
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
    "nvim-tree/nvim-web-devicons",
  },
}

function M.config()
  local ok, octo = pcall(require, "octo")
  if not ok then
    return
  end
  octo.setup()
end

return M
