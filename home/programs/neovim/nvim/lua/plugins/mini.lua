local M = {
  "echasnovski/mini.nvim",
}

function M.config()
  local ok, surround = pcall(require, "mini.surround")
  if not ok then
    return
  end

  surround.setup({}) -- Surround mappings like vim-sandwich and vim-surround
  require("mini.trailspace").setup({}) -- Highlight and remove trailing spaces

  require("mini.jump2d").setup({
    -- Characters used for labels of jump spots (in supplied order)
    labels = "asdfghjkl;",

    -- Which lines are used for computing spots
    allowed_lines = {
      blank = true, -- Blank line (not sent to spotter even if `true`)
      cursor_before = true, -- Lines before cursor line
      cursor_at = true, -- Cursor line
      cursor_after = true, -- Lines after cursor line
      fold = true, -- Start of fold (not sent to spotter even if `true`)
    },

    -- Module mappings. Use `''` (empty string) to disable one.
    mappings = {
      start_jumping = "<CR>",
    },
  })
end

return M
