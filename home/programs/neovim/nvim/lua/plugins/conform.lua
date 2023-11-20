return {
  dir = "~/.local/share/nvim/nix/conform.nvim",
  opts = {},
  event = { "BufWritePre" },
  cmd = {
    "ConformInfo",
    "FormatDisable",
    "FormatEnable",
    "Format",
  },
  config = function()
    require("conform").setup({
      format_on_save = function(bufnr)
        local ignore_filetypes = { "helm" }

        if vim.tbl_contains(ignore_filetypes, vim.bo[bufnr].filetype) then
          return
        end

        -- Disable with a global or buffer-local variable
        if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
          return
        end

        -- Disable autoformat for files in a certain path
        local bufname = vim.api.nvim_buf_get_name(bufnr)
        if bufname:match("/node_modules/") then
          return
        end

        return { timeout_ms = 500, lsp_fallback = true }
      end,
      formatters_by_ft = {
        go = { "goimports", "golines", "gofmt", "gofumpt" },
        javascript = { { "prettierd", "prettier" } },
        json = { { "jq" } },
        lua = { "stylua" },
        sh = { "shfmt" },
        terraform = { "terraform_fmt" },
        rust = { "rustfmt" },
        python = { "isort", "black" },
      },
    })

    vim.api.nvim_create_user_command("FormatDisable", function(args)
      if args.bang then
        -- FormatDisable! will disable formatting just for this buffer
        vim.b.disable_autoformat = true
      else
        vim.g.disable_autoformat = true
      end
    end, {
      desc = "Disable autoformat-on-save",
      bang = true,
    })
    vim.api.nvim_create_user_command("FormatEnable", function()
      vim.b.disable_autoformat = false
      vim.g.disable_autoformat = false
    end, {
      desc = "Re-enable autoformat-on-save",
    })

    vim.api.nvim_create_user_command("Format", function(args)
      local range = nil
      if args.count ~= -1 then
        local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
        range = {
          start = { args.line1, 0 },
          ["end"] = { args.line2, end_line:len() },
        }
      end
      require("conform").format({ async = true, lsp_fallback = true, range = range })
    end, { range = true })
  end,
}
