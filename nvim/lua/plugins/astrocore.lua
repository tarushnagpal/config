-- AstroCore provides a central place to modify mappings, vim options, autocommands, and more!
-- Configuration documentation can be found with `:h astrocore`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

local function url_under_cursor()
  local line = vim.api.nvim_get_current_line()
  local cursor_col = vim.api.nvim_win_get_cursor(0)[2] + 1

  for start_col, url in line:gmatch "()(https?://%S+)" do
    local end_col = start_col + #url - 1
    if start_col <= cursor_col and cursor_col <= end_col then
      return url:gsub([[[%]%)}>'"`,.;:]+$]], "")
    end
  end
end

local function open_url_on_host()
  local url = url_under_cursor()
  if not url then
    vim.notify("No URL under cursor", vim.log.levels.WARN, { title = "gx" })
    return
  end

  if not vim.env.PLANNOTATOR_LAPTOP_HOST or vim.env.PLANNOTATOR_LAPTOP_HOST == "" then
    vim.notify("PLANNOTATOR_LAPTOP_HOST is not set", vim.log.levels.ERROR, { title = "gx" })
    return
  end

  local opener = vim.env.PLANNOTATOR_BROWSER
  if not opener or opener == "" then opener = vim.fn.expand "~/.config/opencode/scripts/plannotator-browser.sh" end

  if vim.fn.executable(opener) ~= 1 then
    local fallback = "/home/ubuntu/workspace/personal/config/opencode/scripts/plannotator-browser.sh"
    if vim.fn.executable(fallback) == 1 then
      opener = fallback
    else
      vim.notify("Cannot find plannotator-browser.sh", vim.log.levels.ERROR, { title = "gx" })
      return
    end
  end

  local job = vim.fn.jobstart({ opener, url }, { detach = true })
  if job <= 0 then
    vim.notify("Failed to launch host URL opener", vim.log.levels.ERROR, { title = "gx" })
  else
    vim.notify("Opening on host: " .. url, vim.log.levels.INFO, { title = "gx" })
  end
end

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

        -- Reuse the OpenCode/Plannotator host-browser bridge for app-server links.
        gx = { open_url_on_host, desc = "Open URL on host" },
      },
    },
  },
}
