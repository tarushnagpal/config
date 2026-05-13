-- Snacks picker uses buffer-local mappings, so global IJKL remaps do not
-- apply inside grep/file/search result windows unless we override them here.

---@type LazySpec
return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      win = {
        input = {
          keys = {
            ["i"] = { "list_up", mode = "n" },
            ["k"] = { "list_down", mode = "n" },
            ["j"] = { "preview_scroll_left", mode = "n" },
            ["l"] = { "preview_scroll_right", mode = "n" },
            [";"] = { function() vim.cmd.startinsert() end, mode = "n", desc = "Insert mode" },
          },
        },
        list = {
          keys = {
            ["i"] = "list_up",
            ["k"] = "list_down",
            ["j"] = "preview_scroll_left",
            ["l"] = "preview_scroll_right",
            [";"] = "focus_input",
          },
        },
        preview = {
          keys = {
            ["i"] = "preview_scroll_up",
            ["k"] = "preview_scroll_down",
            ["j"] = "preview_scroll_left",
            ["l"] = "preview_scroll_right",
            [";"] = "focus_input",
          },
        },
      },
    },
  },
}
