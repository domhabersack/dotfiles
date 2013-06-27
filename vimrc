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
let g:solarized_termcolors=256
colorscheme solarized

" line numbers
set number

" always show current position
set ruler

" show gutter after column 80
set colorcolumn=81

" soft tabs
set expandtab
set shiftwidth=2
set softtabstop=2

" always use autoindenting
set autoindent

" highlight unwanted whitespace
highlight ExtraWhitespace ctermbg=red
match ExtraWhitespace /\s\+$\| \+\ze\t/

" highlight search results
set hlsearch

" not entirely sure what this does
filetype plugin indent on
