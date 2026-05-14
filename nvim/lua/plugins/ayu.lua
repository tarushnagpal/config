---@type LazySpec
return {
  "Shatur/neovim-ayu",
  lazy = false,
  priority = 1000,
  main = "ayu",
  opts = {
    mirage = false,
    terminal = true,
    overrides = {
      Normal = { bg = "#0b0e14", fg = "#bfbdb6" },
      NormalFloat = { bg = "#11151c", fg = "#bfbdb6" },
      FloatBorder = { bg = "#11151c", fg = "#53bdfa" },
      SignColumn = { bg = "#0b0e14" },
    },
  },
}
