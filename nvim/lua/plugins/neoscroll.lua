-- Smooth scrolling for window movement commands
return {
  "karb94/neoscroll.nvim",
  event = "VeryLazy",
  opts = {
    duration_multiplier = 0.4, -- 40% of default duration (much snappier)
    easing = "quadratic",      -- smooth deceleration at the end
  },
}
