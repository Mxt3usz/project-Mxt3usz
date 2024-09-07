local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local opts = {}

local plugins = {
    {
    'nvim-telescope/telescope.nvim', tag = '0.1.5',
    				     branch = '0.1.x',
      dependencies = { 'nvim-lua/plenary.nvim' },
    },
    {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function ()
      local configs = require("nvim-treesitter.configs")

      configs.setup({
          ensure_installed = { "c", "lua", "python", "vim", "vimdoc", "query" },
          sync_install = false,
          highlight = { enable = true },
          indent = { enable = true },
        })
    end
    },
    {
     "catppuccin/nvim", name = "catppucin", priority = 1000
    },
}

require("lazy").setup(plugins, opts)
vim.cmd.colorscheme "catppuccin"


local builtin = require('telescope.builtin')
vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
-- map <leader> + g to get_selection (<leader> = \)
vim.keymap.set("n", "<leader>g", ':lua require"MagiSnipp".get_selection()<cr>')
-- map <leader> + o to open_mappings_window
vim.keymap.set("n", "<leader>o", ':lua require"MagiSnipp".open_mappings_window()<cr>')