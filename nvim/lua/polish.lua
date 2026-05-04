-- This will run last in the setup process, after all plugins are loaded.
-- IJKL navigation remaps live here so they cleanly overwrite any plugin
-- mappings (e.g. AstroNvim's expr-based smart j/k) without merge issues.

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  IJKL Navigation Remap (inverted-T layout)                 ║
-- ║                                                            ║
-- ║    j = left   (was h)    ;  = insert mode (was i)          ║
-- ║    l = right  (unchanged) K = join lines  (was J)          ║
-- ║    i = up     (was k)    U = redo         (was <C-r>)      ║
-- ║    k = down   (was j)                                      ║
-- ║                                                            ║
-- ║  Operator-pending mode is NOT remapped — ciw, di(, yi"     ║
-- ║  still use i as "inner".                                   ║
-- ╚══════════════════════════════════════════════════════════════╝

local map = vim.keymap.set

-- Core movement (normal + visual)
map({ "n", "v" }, "i", "k", { noremap = true, desc = "Move up" })
map({ "n", "v" }, "k", "j", { noremap = true, desc = "Move down" })
map({ "n", "v" }, "j", "h", { noremap = true, desc = "Move left" })
-- l = right (already default, no remap needed)

-- Displaced keys (normal only)
map("n", ";", "i", { noremap = true, desc = "Insert mode" })
map("n", "K", "J", { noremap = true, desc = "Join lines" })
map("n", "U", "<C-r>", { noremap = true, desc = "Redo" })

-- Terminal mode: double-Esc exits to normal mode (single Esc reserved for terminal programs)
map("t", "<Esc><Esc>", "<C-\\><C-n>", { noremap = true, desc = "Exit terminal mode" })
