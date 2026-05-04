---@type LazySpec
return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
  keys = {
    { "<Leader>gd", "<Cmd>DiffviewOpen<CR>", desc = "Open Diffview" },
    { "<Leader>gh", "<Cmd>DiffviewFileHistory %<CR>", desc = "File history (current)" },
    { "<Leader>gH", "<Cmd>DiffviewFileHistory<CR>", desc = "File history (repo)" },
    { "<Leader>gq", "<Cmd>DiffviewClose<CR>", desc = "Close Diffview" },
  },
  opts = {},
}
