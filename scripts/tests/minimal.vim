" Test environment setup
set rtp+=.
if exists("$PLENARY_PATH")
  let &rtp = $PLENARY_PATH . "," . &rtp
  execute "set rtp+=" . $PLENARY_PATH . "/lua"
endif

" Fallback paths for non-nix environments
set rtp+=../plenary.nvim
set rtp+=~/.local/share/nvim/site/pack/packer/start/plenary.nvim
set rtp+=~/.local/share/nvim/lazy/plenary.nvim

set autoindent
set tabstop=4
set expandtab
set shiftwidth=4
set noswapfile

runtime! plugin/plenary.vim
