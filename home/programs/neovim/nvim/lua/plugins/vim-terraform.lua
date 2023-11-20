local M = {
  dir = "~/.local/share/nvim/nix/terraform",
  lazy = true,
  ft = "terraform",
}

function M.config()
  vim.g.hcl_align = 1
  vim.g.terraform_align = 1
  vim.g.terraform_fmt_on_save = 1
end

return M
