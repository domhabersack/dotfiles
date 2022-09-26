" use vim-settings rather then vi-settings
set nocompatible

" required by Vundle
filetype off

""""""""""""""""""""""""""""""""
" Vundle
""""""""""""""""""""""""""""""""

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim

call vundle#begin()

Plugin 'VundleVim/Vundle.vim'

Plugin    'ctrlpvim/ctrlp.vim'
Plugin       'mattn/emmet-vim'
Plugin      'othree/html5.vim'
Plugin  'scrooloose/nerdtree'
Plugin     'myusuf3/numbers.vim'
Plugin      'tomtom/tcomment_vim'
Plugin 'leafgarland/typescript-vim'
Plugin      'SirVer/ultisnips'
Plugin 'altercation/vim-colors-solarized'
Plugin          'ap/vim-css-color'
Plugin    'airblade/vim-gitgutter'
Plugin    'pangloss/vim-javascript'
Plugin       'yuezk/vim-js'
Plugin   'maxmellon/vim-jsx-pretty'
Plugin     'kshenoy/vim-signature'
Plugin       'tpope/vim-surround'

call vundle#end()

" also required by Vundle
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
colorscheme solarized

" toggle background with key
call togglebg#map("<F5>")

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
" gitgutter
""""""""""""""""""""""""""""""""

" give sign column the same background color as the line number column
hi! link SignColumn LineNr

" reduce update time so signs appear faster (also controls delay before vim writes its swap file)
set updatetime=100


""""""""""""""""""""""""""""""""
" JSX
""""""""""""""""""""""""""""""""

"let g:jsx_ext_required = 0


""""""""""""""""""""""""""""""""
" NERDTree
""""""""""""""""""""""""""""""""

let g:ctrlp_dont_split = 'nerdtree'
let g:NERDTreeWinSize = 48
map <C-n> :NERDTreeToggle<CR>


""""""""""""""""""""""""""""""""
" numbers.vim
""""""""""""""""""""""""""""""""

let g:numbers_exclude = ['nerdtree']
nnoremap <F3> :NumbersToggle<CR>


""""""""""""""""""""""""""""""""
" vim-jsx-pretty
""""""""""""""""""""""""""""""""

" nothing so far


""""""""""""""""""""""""""""""""
" ultisnips
""""""""""""""""""""""""""""""""

let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"


""""""""""""""""""""""""""""""""
" Other mappings
""""""""""""""""""""""""""""""""

" toggle `set list`
nmap <leader>l :set list!<CR>
