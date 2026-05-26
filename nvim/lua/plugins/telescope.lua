-- Telescope starts in insert mode so the search prompt remains typeable.
-- Use Ctrl-based IJKL movement there, and plain IJKL only after pressing Esc.

---@type LazySpec
return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    {
      "nvim-telescope/telescope-live-grep-args.nvim",
      version = "^1.0.0",
    },
  },
  specs = {
    {
      "AstroNvim/astrocore",
      opts = function(_, opts)
        local maps = opts.mappings

        maps.n["<Leader>fc"] = {
          function() require("telescope-live-grep-args.shortcuts").grep_word_under_cursor() end,
          desc = "Find word under cursor",
        }
        maps.n["<Leader>fw"] = {
          function() require("telescope").extensions.live_grep_args.live_grep_args() end,
          desc = "Find words",
        }
        maps.n["<Leader>fW"] = {
          function()
            require("telescope").extensions.live_grep_args.live_grep_args {
              additional_args = function() return { "--hidden", "--no-ignore" } end,
            }
          end,
          desc = "Find words in all files",
        }
      end,
    },
  },
  opts = function(_, opts)
    local actions = require "telescope.actions"
    local lga_actions = require "telescope-live-grep-args.actions"

    opts.defaults = opts.defaults or {}
    opts.defaults.file_ignore_patterns = vim.list_extend(opts.defaults.file_ignore_patterns or {}, {
      "node_modules/",
      "%.git/",
      "dist/",
      "build/",
      "%.lock$",
    })

    opts.defaults.mappings = opts.defaults.mappings or {}
    opts.defaults.mappings.i = vim.tbl_extend("force", opts.defaults.mappings.i or {}, {
      ["<C-i>"] = actions.move_selection_previous,
      ["<C-k>"] = actions.move_selection_next,
    })
    opts.defaults.mappings.n = vim.tbl_extend("force", opts.defaults.mappings.n or {}, {
      i = actions.move_selection_previous,
      k = actions.move_selection_next,
      j = actions.close,
      l = actions.select_default,
    })

    opts.extensions = opts.extensions or {}
    opts.extensions.live_grep_args = vim.tbl_extend("force", opts.extensions.live_grep_args or {}, {
      auto_quoting = true,
      mappings = {
        i = {
          ["<C-g>"] = lga_actions.quote_prompt(),
          ["<C-l>"] = lga_actions.quote_prompt { postfix = " --iglob " },
          ["<C-Space>"] = lga_actions.to_fuzzy_refine,
        },
      },
    })

    return opts
  end,
  config = function(_, opts)
    local telescope = require "telescope"
    telescope.setup(opts)
    telescope.load_extension "live_grep_args"
  end,
}
