-- Snacks picker uses buffer-local mappings, so global IJKL remaps do not
-- apply inside grep/file/search result windows unless we override them here.
-- Snacks picker panes define their own buffer-local mappings, so global IJKL
-- movement from polish.lua cannot override them. Configure the picker windows
-- directly while leaving insert-mode search input untouched.

---@type LazySpec
return {
	"folke/snacks.nvim",
	opts = {
		picker = {
			win = {
				input = {
					keys = {
						["i"] = { "list_up", mode = "n" },
						["k"] = { "list_down", mode = "n" },
						[";"] = {
							function()
								vim.cmd.startinsert()
							end,
							mode = "n",
							desc = "Insert mode",
						},
						["j"] = false,
						["l"] = { "confirm", mode = "n" },
					},
				},
				list = {
					keys = {
						["i"] = "list_up",
						["k"] = "list_down",
						[";"] = "focus_input",
						["j"] = false,
						["l"] = "confirm",
						["/"] = "focus_input",
					},
				},
				preview = {
					keys = {
						["i"] = "preview_scroll_up",
						["k"] = "preview_scroll_down",
						["l"] = "preview_scroll_right",
						[";"] = "focus_input",
						["j"] = false,
						["/"] = "focus_input",
					},
				},
			},
		},
	},
}
