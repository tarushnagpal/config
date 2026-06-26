---@type LazySpec
return {
  {
    "vuki656/package-info.nvim",
    opts = function(_, opts)
      opts = opts or {}
      opts.autostart = false
      return opts
    end,
    config = function(_, opts)
      require("package-info").setup(opts)

      vim.api.nvim_create_autocmd("BufEnter", {
        group = vim.api.nvim_create_augroup("UserPackageInfoAutostart", { clear = true }),
        pattern = "package.json",
        desc = "Show package info for real package.json files",
        callback = function()
          local dir = vim.fn.expand "%:p:h"
          local stat = (vim.uv or vim.loop).fs_stat(dir)

          if not stat or stat.type ~= "directory" then return end

          require("package-info").show()
        end,
      })
    end,
  },
}
