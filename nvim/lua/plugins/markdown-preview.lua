---@type LazySpec
return {
	"iamcco/markdown-preview.nvim",
	cmd = { "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" },
	build = function()
		vim.fn["mkdp#util#install"]()
	end,
	ft = { "markdown" },
	init = function()
		vim.g.mkdp_filetypes = { "markdown" }
	end,
	keys = {
		{ "<Leader>mp", "<Cmd>MarkdownPreviewToggle<CR>", desc = "Markdown preview" },
	},
}
