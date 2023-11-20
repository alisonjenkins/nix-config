local M = {
  "aspeddro/pandoc.nvim",
  lazy = true,
  dependencies = {
    "nvim-lua/plenary.nvim",
    "jbyuki/nabla.nvim", -- Optional. See Extra Features
  },
}

function M.config()
  local ok, pandoc = pcall(require, "pandoc")

  if not ok then
    return
  end

  pandoc.setup()
end

return M
