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
  opts = function()
    local actions = require "diffview.actions"

    return {
      keymaps = {
        view = {
          { "n", "<Leader>o", actions.focus_files, { desc = "Focus Diffview file panel" } },
        },
        file_panel = {
          { "n", "<Leader>o", actions.focus_files, { desc = "Focus Diffview file panel" } },
          { "n", "<Leader>e", actions.close, { desc = "Close Diffview file panel" } },
          { "n", "i", actions.prev_entry, { desc = "Previous entry" } },
          { "n", "k", actions.next_entry, { desc = "Next entry" } },
          { "n", "j", actions.close_fold, { desc = "Collapse fold" } },
          { "n", "l", actions.select_entry, { desc = "Open entry" } },
          { "n", "I", actions.listing_style, { desc = "Toggle listing style" } },
        },
        file_history_panel = {
          { "n", "<Leader>o", actions.focus_files, { desc = "Focus Diffview file panel" } },
          { "n", "<Leader>e", actions.close, { desc = "Close Diffview file panel" } },
          { "n", "i", actions.prev_entry, { desc = "Previous entry" } },
          { "n", "k", actions.next_entry, { desc = "Next entry" } },
          { "n", "j", actions.close_fold, { desc = "Collapse fold" } },
          { "n", "l", actions.select_entry, { desc = "Open entry" } },
        },
      },
    }
  end,
}
