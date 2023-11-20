local M = {
  dir = "~/.local/share/nvim/nix/neorg",
  build = ":Neorg sync-parsers",
  lazy = true,
  cmd = {
    "Neorg",
  },
  ft = "norg",
  dependencies = {dir = "~/.local/share/nvim/nix/plenary"},
}

function M.config()
  require"neorg".setup({
    -- Tell Neorg what modules to load
    load = {
      ["core.defaults"] = {},  -- Load all the default modules
      ["core.ui.calendar"] = {},
      ["core.concealer"] = {}, -- Allows for use of icons
      ["core.completion"] = {
        config = {
          engine = "nvim-cmp",
          name = "[Neorg]",
        }
      },
      ["core.dirman"] = { -- Manage your directories with Neorg
        config = {
          workspaces = {
            personal = "~/Documents/Notes/Personal",
            work = "~/Documents/Notes/Work",
          },
        },
      },
      ["core.summary"] = {
        config = {
          strategy = "default",
        }
      },
      -- ["core.gtd.base"] = {
      --   config = {
      --     workspace = "work",
      --   },
      -- },
    },
  })
end

return M
