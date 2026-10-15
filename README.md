# Neovim configuration

My [LazyVim](https://www.lazyvim.org/) configuration, including personal
keymaps and plugin overrides. `lua/plugins/epitech-dump-arch.lua` is a managed
integration from [epitech-dump-arch](https://github.com/cempack/epitech-dump-arch);
its plugin code is installed separately under Neovim's data directory.

To install Neovim, the tools this config needs and the config itself on a new
machine (Arch/Omarchy, Ubuntu/Debian, Fedora, openSUSE or macOS), run:

```sh
bash <(wget -qO- https://raw.githubusercontent.com/cempack/nvim-config/main/install.sh)
```

Re-running it updates everything in place; an existing different config is
moved to `~/.config/nvim.bak.<timestamp>`.

To set it up by hand instead, clone this repository to
`~/.config/nvim`, run the `epitech-dump-arch` installer to populate its managed
plugin path, then start Neovim to install the locked LazyVim plugins.
The Epitech updater does not update LazyVim itself.

The `lua/plugins/theme.lua` symlink follows the current Omarchy theme on an
Omarchy machine; it will not resolve on systems without that theme path.

`<leader>cf` formats C and Makefiles, `<leader>cH` inserts a filetype-aware
Epitech header, and `<leader>cG` adds an include guard to a C header.
