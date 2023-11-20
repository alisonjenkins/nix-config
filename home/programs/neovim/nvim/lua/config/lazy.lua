local lazypath = vim.fn.stdpath("data") .. "/nix/lazy"
vim.opt.rtp:prepend(lazypath)

require("lazy").setup("plugins", {
  git = {
    timeout = 600,
  }
})
