" use vim-settings rather than vi-settings
set nocompatible


""""""""""""""""""""""""""""""""
" vim-plug
""""""""""""""""""""""""""""""""

" auto-install vim-plug on a fresh machine (mirrors TPM / fzf auto-install pattern)
let s:plug_path = has('nvim')
  \ ? stdpath('data') . '/site/autoload/plug.vim'
  \ : expand('~/.vim/autoload/plug.vim')
if empty(glob(s:plug_path))
  silent execute '!curl -fLo ' . s:plug_path .
    \ ' --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'
  autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

call plug#begin()

" UI / navigation
Plug 'preservim/nerdtree'
Plug 'airblade/vim-gitgutter'
Plug 'myusuf3/numbers.vim'
Plug 'kshenoy/vim-signature'

" Editing
Plug 'tpope/vim-surround'
Plug 'tomtom/tcomment_vim'
Plug 'mattn/emmet-vim'
Plug 'ap/vim-css-color'

" Fuzzy finder (fzf binary auto-installed by zshrc)
Plug 'junegunn/fzf'
Plug 'junegunn/fzf.vim'

if has('nvim')
  " LSP + completion + syntax (neovim-only)
  Plug 'neovim/nvim-lspconfig'
  Plug 'williamboman/mason.nvim'
  Plug 'williamboman/mason-lspconfig.nvim'
  Plug 'hrsh7th/nvim-cmp'
  Plug 'hrsh7th/cmp-nvim-lsp'
  Plug 'hrsh7th/cmp-buffer'
  Plug 'hrsh7th/cmp-path'
  Plug 'L3MON4D3/LuaSnip', { 'tag': 'v2.*' }
  Plug 'saadparwaiz1/cmp_luasnip'
  Plug 'nvim-treesitter/nvim-treesitter', { 'do': ':TSUpdate' }
  Plug 'stevearc/conform.nvim'
endif

call plug#end()

filetype plugin indent on


""""""""""""""""""""""""""""""""
" Colors and text
""""""""""""""""""""""""""""""""

" syntax highlighting
syntax enable

" show two lines in status bar
set laststatus=2

" color scheme
set t_Co=256
set background=dark
colorscheme desert

" line numbers
set number

" always show current position
set ruler

" show gutter after column 120
set colorcolumn=121

" highlight current line
set cursorline

" soft tabs
set expandtab
set shiftwidth=2
set softtabstop=2

" always use autoindenting
set autoindent

" show invisibles
set list
set listchars=tab:▸\ ,eol:¬

" highlight unwanted whitespace
highlight ExtraWhitespace ctermbg=red
match ExtraWhitespace /\s\+\%#\@<!$\| \+\ze\t/
autocmd Syntax * syn match ExtraWhitespace /\s\+\%#\@<!$\| \+\ze\t/

" highlight search results
set hlsearch

" case-insensitive search
set ignorecase


""""""""""""""""""""""""""""""""
" Behavior
""""""""""""""""""""""""""""""""

" do not auto-insert comments
autocmd FileType * setlocal formatoptions-=c formatoptions-=r formatoptions-=o

" color status bar when in insert mode
function! InsertStatuslineColor(mode)
  if a:mode == 'i'
    hi statusline ctermfg=DarkGreen ctermbg=Black
  elseif a:mode == 'r'
    hi statusline ctermfg=DarkRed ctermbg=White
  else
    hi statusline ctermfg=Yellow ctermbg=Black
  endif
endfunction

au InsertEnter * call InsertStatuslineColor(v:insertmode)
au InsertChange * call InsertStatuslineColor(v:insertmode)
au InsertLeave * hi statusline ctermfg=Gray ctermbg=Black

" default statusline
hi statusline ctermfg=Gray ctermbg=Black

" preserve indentation while pasting text from OS X clipboard
noremap <leader>p :set paste<CR>:put  *<CR>:set nopaste<CR>


""""""""""""""""""""""""""""""""
" Autocomplete
""""""""""""""""""""""""""""""""

" fallback for plain vim (nvim-cmp takes over in neovim)
set completeopt=longest,menuone

" always select first element in popup
inoremap <expr> <C-n> pumvisible() ? '<C-n>' : '<C-n><C-r>=pumvisible() ? "\<lt>Down>" : ""<CR>'

" change colors of popup
hi Pmenu ctermbg=DarkGray ctermfg=Black
hi PmenuSel ctermbg=Black ctermfg=Green


""""""""""""""""""""""""""""""""
" fzf
""""""""""""""""""""""""""""""""

" Ctrl-P for file picker (muscle-memory from CtrlP), leader shortcuts for grep/buffers
nnoremap <C-p>     :Files<CR>
nnoremap <leader>b :Buffers<CR>
nnoremap <leader>g :Rg<CR>
let g:fzf_layout = { 'down': '40%' }

" exclude heavy dirs; uses fd if installed (auto-installed by zshrc)
let $FZF_DEFAULT_COMMAND = 'fd --type f --hidden --follow --exclude .git --exclude node_modules --exclude .next --exclude dist'


""""""""""""""""""""""""""""""""
" gitgutter
""""""""""""""""""""""""""""""""

" give sign column the same background color as the line number column
hi! link SignColumn LineNr

" reduce update time so signs appear faster (also controls delay before vim writes its swap file)
set updatetime=100


""""""""""""""""""""""""""""""""
" NERDTree
""""""""""""""""""""""""""""""""

let g:NERDTreeWinSize = 48
map <C-n> :NERDTreeToggle<CR>


""""""""""""""""""""""""""""""""
" numbers.vim
""""""""""""""""""""""""""""""""

let g:numbers_exclude = ['nerdtree']
nnoremap <F3> :NumbersToggle<CR>


""""""""""""""""""""""""""""""""
" Other mappings
""""""""""""""""""""""""""""""""

" toggle `set list`
nmap <leader>l :set list!<CR>


""""""""""""""""""""""""""""""""
" LSP (neovim only)
""""""""""""""""""""""""""""""""

if has('nvim')
lua << EOF
-- Mason installs and updates language servers automatically
require('mason').setup()
require('mason-lspconfig').setup({
  ensure_installed = {
    'ts_ls',       -- TypeScript / JavaScript (the new name for tsserver)
    'tailwindcss', -- Tailwind class autocomplete inside className=""
    'eslint',      -- ESLint diagnostics + quick-fix action
    'cssls',       -- CSS
    'html',        -- HTML
    'jsonls',      -- JSON / tsconfig / package.json
  },
})

local lspconfig    = require('lspconfig')
local capabilities = require('cmp_nvim_lsp').default_capabilities()

local on_attach = function(_, bufnr)
  local opts = { buffer = bufnr, silent = true }
  vim.keymap.set('n', 'gd',         vim.lsp.buf.definition,     opts) -- goto definition
  vim.keymap.set('n', 'gD',         vim.lsp.buf.declaration,    opts) -- goto declaration
  vim.keymap.set('n', 'gr',         vim.lsp.buf.references,     opts) -- find references
  vim.keymap.set('n', 'gi',         vim.lsp.buf.implementation, opts) -- goto implementation
  vim.keymap.set('n', 'K',          vim.lsp.buf.hover,          opts) -- hover docs / type info
  vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename,         opts) -- rename symbol
  vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action,    opts) -- code actions
  vim.keymap.set('n', '[d',         vim.diagnostic.goto_prev,   opts) -- prev error/warning
  vim.keymap.set('n', ']d',         vim.diagnostic.goto_next,   opts) -- next error/warning
  vim.keymap.set('n', '<leader>e',  vim.diagnostic.open_float,  opts) -- show error detail
end

for _, server in ipairs({ 'ts_ls', 'tailwindcss', 'eslint', 'cssls', 'html', 'jsonls' }) do
  lspconfig[server].setup({ capabilities = capabilities, on_attach = on_attach })
end

-- diagnostics: inline virtual text + gutter signs + floating preview
vim.diagnostic.config({
  virtual_text     = { prefix = '●' },
  signs            = true,
  underline        = true,
  severity_sort    = true,
  update_in_insert = false,
  float            = { border = 'rounded', source = 'always' },
})

-- nvim-cmp: completion engine (Tab/S-Tab to navigate, Enter to confirm)
local cmp     = require('cmp')
local luasnip = require('luasnip')

cmp.setup({
  snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
  mapping = cmp.mapping.preset.insert({
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<CR>']      = cmp.mapping.confirm({ select = true }),
    ['<Tab>']     = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_next_item()
      elseif luasnip.expand_or_jumpable() then luasnip.expand_or_jump()
      else fallback() end
    end, { 'i', 's' }),
    ['<S-Tab>']   = cmp.mapping(function(fallback)
      if cmp.visible() then cmp.select_prev_item()
      elseif luasnip.jumpable(-1) then luasnip.jump(-1)
      else fallback() end
    end, { 'i', 's' }),
  }),
  sources = cmp.config.sources({
    { name = 'nvim_lsp' }, -- language server completions
    { name = 'luasnip' },  -- snippet completions
    { name = 'buffer' },   -- words in open buffers
    { name = 'path' },     -- filesystem paths
  }),
})

-- treesitter: richer syntax for TypeScript / TSX / JSX / CSS / etc.
require('nvim-treesitter.configs').setup({
  ensure_installed = {
    'typescript', 'tsx', 'javascript',
    'html', 'css', 'json',
    'lua', 'vim', 'vimdoc',
    'yaml', 'markdown', 'markdown_inline',
    'bash', 'gitignore',
  },
  highlight = { enable = true },
  indent    = { enable = true },
})

-- format on save with prettier
require('conform').setup({
  formatters_by_ft = {
    typescript      = { 'prettier' },
    typescriptreact = { 'prettier' },
    javascript      = { 'prettier' },
    javascriptreact = { 'prettier' },
    css             = { 'prettier' },
    html            = { 'prettier' },
    json            = { 'prettier' },
    markdown        = { 'prettier' },
    yaml            = { 'prettier' },
  },
  format_on_save = { timeout_ms = 1000, lsp_fallback = true },
})
EOF
endif


""""""""""""""""""""""""""""""""
" Local
""""""""""""""""""""""""""""""""

if filereadable(expand("~/.vimrc.local"))
  source ~/.vimrc.local
endif
