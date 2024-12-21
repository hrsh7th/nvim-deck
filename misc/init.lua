-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath('data') .. '/lazy/lazy.nvim'
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = 'https://github.com/folke/lazy.nvim.git'
  local out = vim.fn.system({ 'git', 'clone', '--filter=blob:none', '--branch=stable', lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { 'Failed to clone lazy.nvim:\n', 'ErrorMsg' },
      { out, 'WarningMsg' },
      { '\nPress any key to exit...' },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
-- This is also a good place to setup other settings (vim.opt)
vim.g.mapleader = ' '
vim.g.maplocalleader = '\\'

vim.o.hidden = true
vim.o.backup = false
vim.o.undodir = vim.fs.normalize('~/.vimundo')
vim.o.undofile = true
vim.o.swapfile = false
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.ignorecase = true
vim.o.smartcase = true
vim.o.virtualedit = 'all'

-- Author's key-mappings.
do
  vim.keymap.set('t', '<Esc>', '<C-\\><C-n>')
  vim.keymap.set('t', '<Esc><Esc>', '<Esc>')
  vim.keymap.set('n', '<Esc>', '<Cmd>nohlsearch<CR><Cmd>diffupdate<CR><Cmd>mode<CR>')
  vim.keymap.set('n', 'q', '<Cmd>q<CR>')
  vim.keymap.set('n', 'Q', '<Cmd>qall!<CR>')
  vim.keymap.set({ 'n', 'x' }, ';', ':')
  vim.keymap.set({ 'n', 'x' }, 'gj', 'gJ')
  vim.keymap.set({ 'n', 'x' }, '<C-h>', '<C-o>zz')
  vim.keymap.set({ 'n', 'x' }, '<C-l>', '<C-i>zz')
  vim.keymap.set({ 'n', 'x' }, '<', '<LT><LT><Esc>')
  vim.keymap.set({ 'n', 'x' }, '>', '>><Esc>')
  vim.keymap.set({ 'n', 'x' }, 'H', '20h')
  vim.keymap.set({ 'n', 'x' }, 'J', '10j')
  vim.keymap.set({ 'n', 'x' }, 'K', '10k')
  vim.keymap.set({ 'n', 'x' }, 'L', '20l')
  vim.keymap.set({ 'n', 'x' }, '<Leader>h', '<C-w>h')
  vim.keymap.set({ 'n', 'x' }, '<Leader>j', '<C-w>j')
  vim.keymap.set({ 'n', 'x' }, '<Leader>k', '<C-w>k')
  vim.keymap.set({ 'n', 'x' }, '<Leader>l', '<C-w>l')
  vim.keymap.set({ 'n', 'x' }, '<Leader>H', '<Cmd>tabprev<CR>')
  vim.keymap.set({ 'n', 'x' }, '<Leader>L', '<Cmd>tabnext<CR>')
  vim.keymap.set({ 'n', 'x' }, '<Leader>t', '<Cmd>tabclose<CR>')
  vim.keymap.set({ 'n', 'x' }, '<Tab>', '%', { remap = true })
  vim.keymap.set('i', '<C-h>', '<Left>')
  vim.keymap.set('i', '<C-l>', '<Right>')
end

-- Setup lazy.nvim
require('lazy').setup({
  spec = {
    'NStefan002/screenkey.nvim',
    {
      'nvim-treesitter/nvim-treesitter',
      lazy = false,
    },
    {
      'echasnovski/mini.nvim',
      lazy = false,
    },
    {
      'bluz71/vim-nightfly-colors',
      lazy = false,
      config = function()
        vim.cmd.colorscheme('nightfly')
      end,
    },
    {
      'hrsh7th/nvim-deck',
      dir = vim.fn.isdirectory('/root/nvim-deck') > 0 and '/root/nvim-deck' or nil,
      config = function()
        local deck = require('deck')

        require('deck.easy').setup()

        vim.api.nvim_create_autocmd('User', {
          pattern = 'DeckStart',
          callback = function(e)
            local ctx = e.data.ctx --[[@as deck.Context]]
            ctx.keymap('n', '<Esc>', function()
              ctx.set_preview_mode(false)
            end)
            ctx.keymap('n', '<Tab>', deck.action_mapping('choose_action'))
            ctx.keymap('n', '<C-l>', deck.action_mapping('refresh'))
            ctx.keymap('n', 'i', deck.action_mapping('prompt'))
            ctx.keymap('n', 'a', deck.action_mapping('prompt'))
            ctx.keymap('n', '@', deck.action_mapping('toggle_select'))
            ctx.keymap('n', '*', deck.action_mapping('toggle_select_all'))
            ctx.keymap('n', 'p', deck.action_mapping('toggle_preview_mode'))
            ctx.keymap('n', 'd', deck.action_mapping('delete'))
            ctx.keymap('n', '<CR>', deck.action_mapping('default'))
            ctx.keymap('n', 'o', deck.action_mapping('open'))
            ctx.keymap('n', 'O', deck.action_mapping('open_keep'))
            ctx.keymap('n', 's', deck.action_mapping('open_split'))
            ctx.keymap('n', 'v', deck.action_mapping('open_vsplit'))
            ctx.keymap('n', 'N', deck.action_mapping('create'))
            ctx.keymap('n', '<C-u>', deck.action_mapping('scroll_preview_up'))
            ctx.keymap('n', '<C-d>', deck.action_mapping('scroll_preview_down'))
          end,
        })

        vim.keymap.set('n', '<Leader>ff', '<Cmd>Deck files<CR>', { desc = 'Show recent files, buffers, and more' })
        vim.keymap.set('n', '<Leader>gr', '<Cmd>Deck grep<CR>', { desc = 'Start grep search' })
        vim.keymap.set('n', '<Leader>gi', '<Cmd>Deck git<CR>', { desc = 'Open git launcher' })
        vim.keymap.set('n', '<Leader>he', '<Cmd>Deck helpgrep<CR>', { desc = 'Live grep all help tags' })

        vim.keymap.set('n', '<Leader>;', function()
          local ctx = require('deck').get_history()[1]
          if ctx then
            ctx.show()
          end
        end)

        vim.keymap.set('n', '<Leader>n', function()
          local ctx = require('deck').get_history()[1]
          if ctx then
            ctx.set_cursor(ctx.get_cursor() + 1)
            ctx.do_action('default')
          end
        end)
      end,
    },
  },
  -- automatically check for plugin updates
  checker = { enabled = true },
})
