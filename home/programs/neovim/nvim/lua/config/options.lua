-- ensure the above directories exist
vim.loop.fs_mkdir(vim.o.backupdir, 750)
vim.loop.fs_mkdir(vim.o.directory, 750)
vim.loop.fs_mkdir(vim.o.undodir, 750)

vim.g.mapleader = " "
vim.g.maplocalleader = ","
vim.o.backup = true                                      -- enable backups so if Neovim crashes or you lose power you do not lose your work.
vim.o.backupdir = vim.fn.stdpath("data") ..
"/backup"                                                -- set backup directory to be a subdirectory of data to ensure that backups are not written to git repos
vim.o.cmdheight = 2                                      -- More space for displaying messages
vim.o.colorcolumn = "80"                                 -- Sets the color column to 80 characters for visual aid
vim.o.completeopt = "menu,menuone,noselect"              -- Completeopt setting recommended by nvim-cmp docs.
vim.o.conceallevel = 0                                   -- So that I can see `` in markdown files
vim.o.cursorline = true                                  -- Enable highlighting of the current line
vim.o.directory = vim.fn.stdpath("data") ..
"/directory"                                             -- Configure 'directory' to ensure that Neovim swap files are not written to repos.
vim.o.expandtab = true                                   -- Converts tabs to spaces
--vim.o.foldclose = "true"
vim.o.foldenable = true
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
-- vim.o.guioptions = "gmrLT" -- Use showtabline in gui vim
vim.o.ignorecase = true                           -- ignore case makes searching case insensitive by default. Overridable by using a capital letter thanks to smart case.
vim.o.laststatus = 3                              -- only show one shared statusline
vim.o.mouse = "a"                                 -- Enable your mouse
vim.o.number = true                               -- set numbered lines
vim.o.pumheight = 0                               -- Sets popup menu height to use available screen space
vim.o.relativenumber = true                       -- set relative numbered lines
vim.o.sessionoptions = vim.o.sessionoptions .. ",globals"
vim.o.showtabline = 1                             -- Show tabline when there is more than 1 tab.
vim.o.signcolumn = "yes"                          -- Always show the signcolumn, otherwise it would shift the text each time
vim.o.smartcase = true                            -- smartcase makes it so that searching becomes case sensitive if you use a capital letter in the search.
vim.o.spell = true                                -- enable spell checking
vim.o.sw = 2                                      -- Set shiftwidth
vim.o.t_Co = 256                                  -- Support 256 colors
vim.o.termguicolors = true                        -- set term gui colors most terminals support this
vim.o.timeoutlen = 300                            -- By default timeoutlen is 1000 ms
vim.o.ts = 2                                      -- Set tabstop
vim.o.undodir = vim.fn.stdpath("data") .. "/undo" -- set undodir to ensure that the undofiles are not saved to git repos.
vim.o.undofile = true                             -- enable persistent undo (meaning if you quit Neovim and come back to a file and want to undo previous changes you can)
vim.o.updatetime = 300                            -- Faster completion
vim.o.wrap = false                                -- Display long lines as just one line
vim.o.writebackup = true                          -- enable writing of backup files when saving changes.
