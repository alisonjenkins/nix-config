local M = {
  "zakharykaplan/nvim-retrail",
}

function M.config()
  require("retrail").setup({
    filetype = {
      exclude = {
        "alpha",
        "diff",
        "dirvish",
        "help",
      },
    },
  })
end

return M
