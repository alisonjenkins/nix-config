local M = {
  dir = "~/.local/share/nvim/nix/terraform-completion",
  lazy = true,
  ft = "terraform",
}

function M.config()
  vim.g.syntastic_terraform_tffilter_plan = 0
  vim.g.terraform_completion_keys = 1
  vim.g.terraform_registry_module_completion = 1
end

return M
