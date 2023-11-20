return {
  dir = "~/.local/share/nvim/nix/lsp-zero",
  dependencies = {
    { dir = "~/.local/share/nvim/nix/lspconfig" },
    {
      dir = "~/.local/share/nvim/nix/mason",
      build = function()
        pcall(vim.cmd, "MasonUpdate")
      end,
    },
    {
      dir = "~/.local/share/nvim/nix/navigator",
      dependencies = {
        { dir = "~/.local/share/nvim/nix/guihua" },
        { dir = "~/.local/share/nvim/nix/lspconfig" },
        { dir = "~/.local/share/nvim/nix/treesitter" },
      },
    },
    {
      dir = "~/.local/share/nvim/nix/ufo",
      dependencies = {
        { dir = "~/.local/share/nvim/nix/promise-async" },
      },
      config = true,
    },
    { dir = "~/.local/share/nvim/nix/mason-lspconfig" },
    { dir = "~/.local/share/nvim/nix/cmp" },
    { dir = "~/.local/share/nvim/nix/cmp-nvim-lsp" },
    { dir = "~/.local/share/nvim/nix/luasnip" },
    { dir = "~/.local/share/nvim/nix/rust-tools" },
     -- "MunifTanjim/rust-tools.nvim", branch = "patched" },
  },
  config = function()
    local lsp_zero = require("lsp-zero")

    lsp_zero.on_attach(function(client, bufnr)
      -- see :help lsp-zero-keybindings
      -- to learn the available actions
      lsp_zero.default_keymaps({
        buffer = bufnr,
        preserve_mappings = false,
      })
      vim.keymap.set("n", "gr", "<cmd>Telescope lsp_references<cr>", { buffer = true })
    end)

    local exclude_formatting_lsps = {
      "copilot",
      "groovyls",
    }

    lsp_zero.set_sign_icons({
      error = "✘",
      warn = "▲",
      hint = "⚑",
      info = "»",
    })

    lsp_zero.set_server_config({
      capabilities = {
        textDocument = {
          foldingRange = {
            dynamicRegistration = false,
            rangeLimit = 1000,
            lineFoldingOnly = true,
          },
        },
      },
    })

    require("mason").setup({})
    require("mason-lspconfig").setup({
      ensure_installed = {},
      handlers = {
        lsp_zero.default_setup,
        rust_analyzer = function()
          local rust_tools = require("rust-tools")

          local codelldb_extension_path = vim.fn.glob(vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/")
            or ""
          local codelldb_path = codelldb_extension_path .. "adapter/codelldb"
          local liblldb_path = codelldb_extension_path .. "lldb/lib/liblldb.so"
          local opts = {
            server = {
              on_attach = function(client, bufnr)
                vim.keymap.set("n", "<leader>ca", rust_tools.hover_actions.hover_actions, { buffer = bufnr })
              end,
            },
          }

          if vim.fn.filereadable(codelldb_path) and vim.fn.filereadable(liblldb_path) then
            opts.dap = {
              adapter = require("rust-tools.dap").get_codelldb_adapter(codelldb_path, liblldb_path),
            }
          else
            local msg = "Either codelldb or liblldb is not readable."
              .. "\n codelldb: "
              .. codelldb_path
              .. "\n liblldb: "
              .. liblldb_path
            vim.notify(msg, vim.log.levels.ERROR)
          end

          rust_tools.setup(opts)
        end,
      },
    })

    require("navigator").setup({
      preview_height = 0.35, -- max height of preview windows
      ts_fold = true, -- modified version of treesitter folding
      default_mapping = false, -- set to false if you will remap every key or if you using old version of nvim-
      treesitter_analysis = true, -- treesitter variable context
      treesitter_navigation = true, -- bool|table false: use lsp to navigate between symbol ']r/[r', table: a list of
      treesitter_analysis_max_num = 100,
      treesitter_analysis_condense = true,
      transparency = 50,
      lsp_signature_help = true, -- if you would like to hook ray-x/lsp_signature plugin in navigator
      -- setup here. if it is nil, navigator will not init signature help
      signature_help_cfg = nil, -- if you would like to init ray-x/lsp_signature plugin in navigator, and pass in your own config to signature help
      icons = {
        -- Code action
        code_action_icon = "🏏", -- note: need terminal support, for those not support unicode, might crash
        -- Diagnostics
        diagnostic_head = "🐛",
        diagnostic_head_severity_1 = "🈲",
        -- refer to lua/navigator.lua for more icons setups
      },
      mason = true, -- set to true if you would like use the lsp installed by williamboman/mason
      lsp = {
        enable = true, -- skip lsp setup, and only use treesitter in navigator.
        -- Use this if you are not using LSP servers, and only want to enable treesitter support.
        -- If you only want to prevent navigator from touching your LSP server configs,
        -- use `disable_lsp = "all"` instead.
        -- If disabled, make sure add require('navigator.lspclient.mapping').setup({bufnr=bufnr, client=client}) in your
        -- own on_attach
        code_action = { enable = true, sign = true, sign_priority = 40, virtual_text = true },
        code_lens_action = { enable = true, sign = true, sign_priority = 40, virtual_text = true },
        document_highlight = true, -- LSP reference highlight,
        -- it might already supported by you setup, e.g. LunarVim
        format_on_save = false, -- {true|false} set to false to disasble lsp code format on save (if you are using prettier/efm/formater etc)
        -- table: {enable = {'lua', 'go'}, disable = {'javascript', 'typescript'}} to enable/disable specific language
        -- enable: a whitelist of language that will be formatted on save
        -- disable: a blacklist of language that will not be formatted on save
        -- function: function(bufnr) return true end to enable/disable lsp format on save
        format_options = { async = true }, -- async: disable by default, the option used in vim.lsp.buf.format({async={true|false}, name = 'xxx'})
        diagnostic = {
          underline = true,
          virtual_text = true, -- show virtual for diagnostic message
          update_in_insert = false, -- update diagnostic message in insert mode
        },
        diagnostic_scrollbar_sign = { "▃", "▆", "█" }, -- experimental:  diagnostic status in scroll bar area; set to false to disable the diagnostic sign,
        diagnostic_virtual_text = true, -- show virtual for diagnostic message
        diagnostic_update_in_insert = false, -- update diagnostic message in insert mode
        display_diagnostic_qf = true, -- always show quickfix if there are diagnostic errors, set to false if you want to ignore it
      },
    })
  end,
}
