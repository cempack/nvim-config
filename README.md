# Neovim configuration

My [LazyVim](https://www.lazyvim.org/) configuration, including personal
keymaps and plugin overrides. `lua/plugins/epitech-dump-arch.lua` is a managed
integration from [epitech-dump-arch](https://github.com/cempack/epitech-dump-arch);
its plugin code is installed separately under Neovim's data directory.

To use this config on a new machine, clone this repository to
`~/.config/nvim`, start Neovim once to install the locked LazyVim plugins,
then run the `epitech-dump-arch` installer for the Epitech integration.
The Epitech updater does not update LazyVim itself.

`<leader>cf` formats C and Makefiles, `<leader>cH` inserts a filetype-aware
Epitech header, and `<leader>cG` adds an include guard to a C header.
