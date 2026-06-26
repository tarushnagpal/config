---@type LazySpec
return {
  "jake-stewart/multicursor.nvim",
  branch = "1.0",
  config = function()
    local mc = require "multicursor-nvim"
    mc.setup()

    local set = vim.keymap.set
    local opts = { silent = true }
    local function desc(text) return vim.tbl_extend("force", opts, { desc = text }) end

    -- IJKL-friendly line cursor actions. These deliberately live under
    -- <Leader>m so normal i/k movement stays untouched.
    set({ "n", "x" }, "<Leader>mi", function() mc.lineAddCursor(-1) end, desc "Add cursor above")
    set({ "n", "x" }, "<Leader>mk", function() mc.lineAddCursor(1) end, desc "Add cursor below")
    set({ "n", "x" }, "<Leader>mI", function() mc.lineSkipCursor(-1) end, desc "Skip cursor above")
    set({ "n", "x" }, "<Leader>mK", function() mc.lineSkipCursor(1) end, desc "Skip cursor below")

    -- Arrow-key equivalents from the plugin README.
    set({ "n", "x" }, "<Up>", function() mc.lineAddCursor(-1) end, desc "Add cursor above")
    set({ "n", "x" }, "<Down>", function() mc.lineAddCursor(1) end, desc "Add cursor below")
    set({ "n", "x" }, "<Leader><Up>", function() mc.lineSkipCursor(-1) end, desc "Skip cursor above")
    set({ "n", "x" }, "<Leader><Down>", function() mc.lineSkipCursor(1) end, desc "Skip cursor below")

    -- Add or skip cursors by matching the current word or visual selection.
    set({ "n", "x" }, "<Leader>mn", function() mc.matchAddCursor(1) end, desc "Add next match cursor")
    set({ "n", "x" }, "<Leader>mN", function() mc.matchAddCursor(-1) end, desc "Add previous match cursor")
    set({ "n", "x" }, "<Leader>ms", function() mc.matchSkipCursor(1) end, desc "Skip next match cursor")
    set({ "n", "x" }, "<Leader>mS", function() mc.matchSkipCursor(-1) end, desc "Skip previous match cursor")
    set({ "n", "x" }, "<Leader>ma", mc.matchAllAddCursors, desc "Add all match cursors")

    -- Cursor management.
    set({ "n", "x" }, "<C-q>", mc.toggleCursor, desc "Toggle multicursor")
    set({ "n", "x" }, "<Leader>md", mc.deleteCursor, desc "Delete main cursor")
    set("n", "<Leader>mr", mc.restoreCursors, desc "Restore cursors")
    set("n", "<Leader>m=", mc.alignCursors, desc "Align cursors")
    set({ "n", "x" }, "<Leader>mD", mc.duplicateCursors, desc "Duplicate cursors")

    -- Search-result based cursors.
    set("n", "<Leader>m/n", function() mc.searchAddCursor(1) end, desc "Add next search cursor")
    set("n", "<Leader>m/N", function() mc.searchAddCursor(-1) end, desc "Add previous search cursor")
    set("n", "<Leader>m/s", function() mc.searchSkipCursor(1) end, desc "Skip next search cursor")
    set("n", "<Leader>m/S", function() mc.searchSkipCursor(-1) end, desc "Skip previous search cursor")
    set("n", "<Leader>m/a", mc.searchAllAddCursors, desc "Add all search cursors")

    -- Visual-mode helpers.
    set("x", "<Leader>m|", mc.splitCursors, desc "Split cursors by regex")
    set("x", "<Leader>mm", mc.matchCursors, desc "Match cursors by regex")
    set("x", "<Leader>mt", function() mc.transposeCursors(1) end, desc "Transpose cursors")
    set("x", "<Leader>mT", function() mc.transposeCursors(-1) end, desc "Transpose cursors backward")
    set("x", "<Leader>m;", mc.insertVisual, desc "Insert at visual cursors")
    set("x", "<Leader>mA", mc.appendVisual, desc "Append at visual cursors")

    -- Mouse support from the README.
    set("n", "<C-LeftMouse>", mc.handleMouse, desc "Add/remove cursor")
    set("n", "<C-LeftDrag>", mc.handleMouseDrag, opts)
    set("n", "<C-LeftRelease>", mc.handleMouseRelease, opts)

    -- These mappings only exist while multiple cursors are active. That keeps
    -- normal movement/editing keys free during regular editing.
    mc.addKeymapLayer(function(layerSet)
      layerSet({ "n", "x" }, "<Left>", mc.prevCursor)
      layerSet({ "n", "x" }, "<Right>", mc.nextCursor)
      layerSet({ "n", "x" }, "<Leader>mj", mc.prevCursor)
      layerSet({ "n", "x" }, "<Leader>ml", mc.nextCursor)
      layerSet({ "n", "x" }, "<Leader>md", mc.deleteCursor)
      layerSet("n", "<Esc>", function()
        if not mc.cursorsEnabled() then
          mc.enableCursors()
        else
          mc.clearCursors()
        end
      end)
    end)

    local hl = vim.api.nvim_set_hl
    hl(0, "MultiCursorCursor", { reverse = true })
    hl(0, "MultiCursorVisual", { link = "Visual" })
    hl(0, "MultiCursorSign", { link = "SignColumn" })
    hl(0, "MultiCursorMatchPreview", { link = "Search" })
    hl(0, "MultiCursorDisabledCursor", { reverse = true })
    hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
    hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
  end,
}
