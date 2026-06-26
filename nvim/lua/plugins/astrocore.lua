-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrocore",
  ---@type AstroCoreOpts
  opts = {
    -- Configure core features of AstroNvim
    features = {
      large_buf = { size = 1024 * 256, lines = 10000 }, -- set global limits for large files for disabling features like treesitter
      autopairs = true, -- enable autopairs at start
      cmp = true, -- enable completion at start
      diagnostics = { virtual_text = true, virtual_lines = false }, -- diagnostic settings on startup
      highlighturl = true, -- highlight URLs at start
      notifications = true, -- enable notifications at start
    },
    -- Diagnostics configuration (for vim.diagnostics.config({...})) when diagnostics are on
    diagnostics = {
      virtual_text = true,
      underline = true,
    },
    autocmds = {
      markdown_wrap = {
        {
          event = "FileType",
          pattern = "markdown",
          desc = "Enable wrap for Markdown buffers",
          callback = function() vim.opt_local.wrap = true end,
        },
      },
    },
    -- vim options can be configured here
    options = {
      opt = { -- vim.opt.<key>
        relativenumber = true, -- sets vim.opt.relativenumber
        number = true, -- sets vim.opt.number
        spell = false, -- sets vim.opt.spell
        signcolumn = "yes", -- sets vim.opt.signcolumn to yes
        wrap = false, -- sets vim.opt.wrap
      },
      g = { -- vim.g.<key>
        -- configure global vim variables (vim.g)
        -- NOTE: `mapleader` and `maplocalleader` must be set in the AstroNvim opts or before `lazy.setup`
        -- This can be found in the `lua/lazy_setup.lua` file
      },
    },
    -- Mappings can be configured through AstroCore as well.
    -- NOTE: keycodes follow the casing in the vimdocs. For example, `<Leader>` must be capitalized
    -- NOTE: IJKL core movement + displaced keys (;, K, U) are in lua/polish.lua
    --       so they run AFTER all plugins and cleanly overwrite AstroNvim's
    --       expr-based smart j/k mappings.
    mappings = {
      n = {
        -- Window navigation and resizing (Leader + w + IJKL)
        ["<Leader>wj"] = { function() require("smart-splits").move_cursor_left() end, desc = "Window left" },
        ["<Leader>wi"] = { function() require("smart-splits").move_cursor_up() end, desc = "Window up" },
        ["<Leader>wk"] = { function() require("smart-splits").move_cursor_down() end, desc = "Window down" },
        ["<Leader>wl"] = { function() require("smart-splits").move_cursor_right() end, desc = "Window right" },
        ["<Leader>wJ"] = { function() require("smart-splits").resize_left() end, desc = "Resize window left" },
        ["<Leader>wI"] = { function() require("smart-splits").resize_up() end, desc = "Resize window up" },
        ["<Leader>wK"] = { function() require("smart-splits").resize_down() end, desc = "Resize window down" },
        ["<Leader>wL"] = { function() require("smart-splits").resize_right() end, desc = "Resize window right" },

        -- Navigate buffer tabs
        ["]b"] = { function() require("astrocore.buffer").nav(vim.v.count1) end, desc = "Next buffer" },
        ["[b"] = { function() require("astrocore.buffer").nav(-vim.v.count1) end, desc = "Previous buffer" },

        -- Close buffer from tabline picker
        ["<Leader>bd"] = {
          function()
            require("astroui.status.heirline").buffer_picker(
              function(bufnr) require("astrocore.buffer").close(bufnr) end
            )
          end,
          desc = "Close buffer from tabline",
        },

        -- Toggle terminal
        ["<Leader>t"] = { "<Cmd>ToggleTerm<CR>", desc = "Toggle terminal" },
      },
    },
  },
}
