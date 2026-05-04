-- Override toggleterm to add <Leader>t as a buffer-local toggle keybind
---@type LazySpec
return {
  "akinsho/toggleterm.nvim",
  opts = {
    ---@param t Terminal
    on_create = function(t)
      vim.opt_local.foldcolumn = "0"
      vim.opt_local.signcolumn = "no"
      local function toggle() t:toggle() end
      -- Buffer-local <Leader>t to close THIS terminal from normal mode
      vim.keymap.set("n", "<Leader>t", toggle, { desc = "Toggle terminal", buffer = t.bufnr })
      if t.hidden then
        vim.keymap.set({ "n", "t", "i" }, "<C-'>", toggle, { desc = "Toggle terminal", buffer = t.bufnr })
        vim.keymap.set({ "n", "t", "i" }, "<F7>", toggle, { desc = "Toggle terminal", buffer = t.bufnr })
      end
    end,
  },
}
