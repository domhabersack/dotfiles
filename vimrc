" load pathogen
execute pathogen#infect()

" use vim-settings rather then vi-settings
set nocompatible

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
colorscheme solarized

" toggle background with key
call togglebg#map("<F5>")

" line numbers
set number

" always show current position
set ruler

" show gutter after column 80
set colorcolumn=81

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

" not entirely sure what this does
filetype plugin indent on


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


""""""""""""""""""""""""""""""""
" Autocomplete
""""""""""""""""""""""""""""""""

" only insert longest common text of matches, show popup even when there is only one match
set completeopt=longest,menuone

" always select first element in popup
inoremap <expr> <C-n> pumvisible() ? '<C-n>' : '<C-n><C-r>=pumvisible() ? "\<lt>Down>" : ""<CR>'

" change colors of popup
hi Pmenu ctermbg=DarkGray ctermfg=Black
hi PmenuSel ctermbg=Black ctermfg=Green


""""""""""""""""""""""""""""""""
" CtrlP
""""""""""""""""""""""""""""""""

let ctrlp_exclude_directories = '\.(hg|git|bzr)|bower_components|node_modules|vendor'
let g:ctrlp_custom_ignore = '\v[\/](' . ctrlp_exclude_directories . ')$'


""""""""""""""""""""""""""""""""
" NERDTree
""""""""""""""""""""""""""""""""

let g:ctrlp_dont_split = 'nerdtree'
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
