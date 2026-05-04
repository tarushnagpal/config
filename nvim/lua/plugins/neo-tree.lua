-- Neo-tree IJKL navigation overrides
--
-- Neo-tree defines its own buffer-local mappings (via window.mappings) that
-- override our global IJKL remaps. By default:
--   - i = show_file_details  (conflicts with our "move up")
--   - h = parent_or_close    (set by AstroNvim, conflicts with IJKL "j = left")
--   - l = child_or_open      (set by AstroNvim, matches IJKL "right")
--
-- This file aligns Neo-tree with the IJKL layout:
--   - i (up) and k (down) fall through to global "move up/down" by clearing
--     Neo-tree's buffer-local bindings
--   - j (left in IJKL) collapses/navigates to parent
--   - l (right) keeps AstroNvim's default expand/open behavior
--   - I (shifted i) is the new home for show_file_details

---@type LazySpec
return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    -- Add diagnostics to initialized sources so source switching doesn't hang
    sources = { "filesystem", "buffers", "git_status", "diagnostics" },
    -- Global mappings (apply to all sources: filesystem, buffers, git_status)
    window = {
      mappings = {
        ["j"] = "parent_or_close", -- IJKL "left" = collapse / go to parent
      },
    },
    -- Filesystem source: free up i, relocate show_file_details to I
    filesystem = {
      window = {
        mappings = {
          ["i"] = false,
          ["I"] = "show_file_details",
        },
      },
    },
    -- Buffers source: same treatment
    buffers = {
      window = {
        mappings = {
          ["i"] = false,
          ["I"] = "show_file_details",
        },
      },
    },
    -- Git status source: same treatment
    git_status = {
      window = {
        mappings = {
          ["i"] = false,
          ["I"] = "show_file_details",
        },
      },
    },
    -- Diagnostics source: same treatment
    diagnostics = {
      window = {
        mappings = {
          ["i"] = false,
          ["I"] = "show_file_details",
        },
      },
    },
  },
}
