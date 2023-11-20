local M = {
  dir = ".local/share/nvim/nix/telescope",
  lazy = true,
  event = "VeryLazy",
  dependencies = {
    dir = ".local/share/nvim/nix/git-worktree",
    dir = ".local/share/nvim/nix/project-nvim",
    -- "crispgm/telescope-heading.nvim",
    dir = ".local/share/nvim/nix/telescope-zoxide",
    dir = ".local/share/nvim/nix/plenary",
    dir = ".local/share/nvim/nix/popup",
    dir = ".local/share/nvim/nix/telescope-dap",
    dir = ".local/share/nvim/nix/telescope-file-browser",
    dir = ".local/share/nvim/nix/telescope-github",
    -- "nvim-telescope/telescope-packer.nvim",
    dir = ".local/share/nvim/nix/telescope-ui-select",
    -- 'piersolenski/telescope-import.nvim',
    { dir = "~/.local/share/nvim/nix/telescope-fzy-native.nvim", dependencies = { dir = ".local/share/nvim/nix/fzy-lua-native" } },
    dir = ".local/share/nvim/nix/nvim-web-devicons",
    -- {
    --   "desdic/macrothis.nvim",
    --   opts = {},
    --   keys = {
    --     { "<Leader>kkd", function() require('macrothis').delete() end, desc = "delete" },
    --     { "<Leader>kke", function() require('macrothis').edit() end, desc = "edit" },
    --     { "<Leader>kkl", function() require('macrothis').load() end, desc = "load" },
    --     { "<Leader>kkn", function() require('macrothis').rename() end, desc = "rename" },
    --     { "<Leader>kkq", function() require('macrothis').quickfix() end, desc = "run macro on all files in quickfix" },
    --     { "<Leader>kkr", function() require('macrothis').run() end, desc = "run macro" },
    --     { "<Leader>kks", function() require('macrothis').save() end, desc = "save" },
    --     { "<Leader>kkx", function() require('macrothis').register() end, desc = "edit register" },
    --     { "<Leader>kkp", function() require('macrothis').copy_register_printable() end, desc = "Copy register as printable" },
    --     { "<Leader>kkm", function() require('macrothis').copy_macro_printable() end, desc = "Copy macro as printable" },
    --   },
    -- },
  }
}

function M.config()
  local hastelescope, telescope = pcall(require, "telescope")

  if not hastelescope then
    return
  end

  local previewers = require("telescope.previewers")

  telescope.setup({
    defaults = {
      border = {},
      borderchars = { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
      color_devicons = true,
      file_ignore_patterns = {},
      file_previewer = previewers.vim_buffer_cat.new,
      file_sorter = require("telescope.sorters").get_fuzzy_file,
      generic_sorter = require("telescope.sorters").get_generic_fuzzy_sorter,
      grep_previewer = previewers.vim_buffer_vimgrep.new,
      initial_mode = "insert",
      layout_strategy = "flex",
      path_display = { "absolute" },
      prompt_prefix = "❱❱ ",
      qflist_previewer = previewers.vim_buffer_qflist.new,
      selection_caret = "❱ ",
      selection_strategy = "reset",
      set_env = { ["COLORTERM"] = "truecolor" }, -- default { }, currently unsupported for shells like cmd.exe / powershell.exe
      sorting_strategy = "descending",
      use_less = false,
      winblend = 0,

      layout_config = {
        horizontal = {
          mirror = false,
          height = 0.9,
        },
        vertical = {
          mirror = false,
          height = 0.9,
        },
      },

      vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
      },
    },
  })

  local extensions = {
    dap = nil,
    file_browser = nil,
    fzy_native = nil,
    gh = nil,
    git_worktree = function()
      require("git-worktree").setup({})
    end,
    projects = function()
      require("project_nvim").setup({
        show_hidden = true,
        ignore_lsp = {
          "null-ls",
        },
      })
    end,
    macrothis = nil,
    ["ui-select"] = function()
      require("telescope.themes").get_dropdown({})
    end,
    zoxide = nil,
  }

  for extension, setup in pairs(extensions) do
    local hasextension, _ = pcall(require, "telescope._extensions." .. extension)

    if hasextension then
      telescope.load_extension(extension)
      if setup ~= nil then
        setup()
      end
    else
      print("Could not load telescope plugin: " .. extension .. " is it installed?")
    end
  end
end

return M
