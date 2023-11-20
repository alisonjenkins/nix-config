local M = {
  dir = "~/.local/share/nvim/nix/fugitive",
  lazy = true,
  cmd = {
    "GBrowse",
    "GDelete",
    "GMove",
    "GRename",
    "Gdiffsplit",
    "Gedit",
    "Ggrep",
    "Git",
    "Glgrep",
    "Gread",
    "Gvdiffsplit",
    "Gwrite",
  },
  dependencies = {
    -- (vimscript) Plugin improve the git commit interface showing diffs to remind you want you are changing.
    dir = ".local/share/nvim/nix/committia",
    -- (vimscript) Adds Fugitive Gbrowse support for Gitlab repos.,
    dir = ".local/share/nvim/nix/fugitive-gitlab",
    -- (vimscript) Adds Fugitive Gbrowse support for Bitbucket repos.
    dir = ".local/share/nvim/nix/fubitive",
    -- (vimscript) Adds Fugitive Gbrowse support for GitHub repos.
    dir = ".local/share/nvim/nix/vim-rhubarb",
  },
}

return M
