local M = {
  "kevinhwang91/nvim-hlslens",
  lazy = true,
  keys = { "/", "?" },
  dependencies = { "nvim-lua/plenary.nvim" },
}

function M.config()
  local ok, hlslens = pcall(require, "hlslens")

  if not ok then
    return
  end

  hlslens.setup()
end

return M
