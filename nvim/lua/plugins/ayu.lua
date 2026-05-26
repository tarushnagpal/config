---@type LazySpec
return {
  "Shatur/neovim-ayu",
  lazy = false,
  priority = 1000,
  main = "ayu",
  opts = {
    mirage = true,
    terminal = true,
    overrides = {
      Normal = { bg = "#1f2430", fg = "#cccac2" },
      NormalFloat = { bg = "#1c212b", fg = "#cccac2" },
      FloatBorder = { bg = "#1c212b", fg = "#73d0ff" },
      SignColumn = { bg = "#1f2430" },
    },
  },
}
