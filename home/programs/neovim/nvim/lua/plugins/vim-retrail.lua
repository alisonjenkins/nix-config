local M = {
  dir = ".local/share/nvim/nix/retrail",
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
