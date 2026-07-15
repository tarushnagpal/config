local background = "#0e1729"
local surface = "#131d30"
local subtle = "#16243d"
local selected = "#243456"
local border = "#526aa3"
local foreground = "#cccac2"

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
      Normal = { bg = background, fg = foreground },
      NormalNC = { bg = background },
      NormalFloat = { bg = surface, fg = foreground },
      FloatBorder = { bg = surface, fg = border },
      SignColumn = { bg = background },
      FoldColumn = { bg = background },
      CursorLine = { bg = subtle },
      Visual = { bg = selected },
      Pmenu = { bg = surface, fg = foreground },
      PmenuSel = { bg = selected, fg = "#dce7f3" },
      StatusLine = { bg = surface, fg = foreground },
      StatusLineNC = { bg = background, fg = border },
      WinSeparator = { bg = background, fg = "#354665" },
    },
  },
}
