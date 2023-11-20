local M = {
  dir = "~/.local/share/nvim/nix/octo",
  lazy = true,
  cmd = "Octo",
  dependencies = {
    dir = "~/.local/share/nvim/nix/plenary",
    dir = "~/.local/share/nvim/nix/telescope",
    dir = "~/.local/share/nvim/nix/nvim-web-devicons",
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
