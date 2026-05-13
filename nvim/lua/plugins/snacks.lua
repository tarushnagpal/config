-- Snacks picker panes define their own buffer-local mappings, so global IJKL
-- movement from polish.lua cannot override them. Configure the picker windows
-- directly while leaving insert-mode search input untouched.

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
            ["j"] = false,
            ["l"] = { "confirm", mode = "n" },
          },
        },
        list = {
          keys = {
            ["i"] = "list_up",
            ["k"] = "list_down",
            ["j"] = false,
            ["l"] = "confirm",
            ["/"] = "focus_input",
          },
        },
        preview = {
          keys = {
            ["i"] = "preview_scroll_up",
            ["k"] = "preview_scroll_down",
            ["j"] = false,
            ["/"] = "focus_input",
          },
        },
      },
    },
  },
}
