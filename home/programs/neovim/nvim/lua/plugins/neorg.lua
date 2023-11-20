local M = {
  "nvim-neorg/neorg",
  build = ":Neorg sync-parsers",
  lazy = true,
  cmd = {
    "Neorg",
  },
  ft = "norg",
  dependencies = "nvim-lua/plenary.nvim",
}

function M.config()
  local ok, neorg = pcall(require, "neorg")

  if not ok then
    return
  end

  neorg.setup({
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
