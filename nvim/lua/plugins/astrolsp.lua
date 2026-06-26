-- AstroLSP allows you to customize the features in AstroNvim's LSP configuration engine
-- Configuration documentation can be found with `:h astrolsp`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    -- mappings to be set up on attaching of a language server
    mappings = {
      n = {
        -- a `cond` key can provided as the string of a server capability to be required to attach, or a function with `client` and `bufnr` parameters from the `on_attach` that returns a boolean
        gD = {
          function() require("telescope.builtin").lsp_references { include_declaration = false } end,
          desc = "Find usages",
          cond = "textDocument/references",
        },
        ["<Leader>lD"] = {
          function() vim.lsp.buf.declaration() end,
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        },
      },
    },
    config = {
      vtsls = {
        root_dir = function(fname)
          if fname:match "^diffview://" or fname:match "^fugitive://" then return nil end

          local util = require "lspconfig.util"
          return util.root_pattern("tsconfig.json", "jsconfig.json")(fname)
            or util.root_pattern("package.json", ".git")(fname)
        end,
        single_file_support = false,
        settings = {
          typescript = {
            tsserver = {
              maxTsServerMemory = 8192,
            },
          },
        },
      },
    },
  },
}
