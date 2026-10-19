# Neovim configuration

My [LazyVim](https://www.lazyvim.org/) configuration, including personal
keymaps and plugin overrides. `lua/plugins/epitech-dump-arch.lua` is the spec
managed by [epitech-dump-arch](https://github.com/cempack/epitech-dump-arch):
lazy.nvim installs the [epitech.nvim](https://github.com/cempack/epitech.nvim)
plugin it points to. Where epitech-dump-arch is installed, its weekly timer
keeps the plugin updated; elsewhere `:Lazy update` or re-running the install
script below does.

To install Neovim, the tools this config needs and the config itself on a new
machine (Arch/Omarchy, Ubuntu/Debian, Fedora, openSUSE or macOS), run:

```sh
bash <(wget -qO- https://raw.githubusercontent.com/cempack/nvim-config/main/install.sh)
```

Re-running it updates everything in place; an existing different config is
moved to `~/.config/nvim.bak.<timestamp>`.

To set it up by hand instead, clone this repository to `~/.config/nvim` and
start Neovim to install the locked LazyVim plugins. The Epitech formatter also
needs `~/.vim/epitech.vim` from [Epitech/vim-epitech](https://github.com/Epitech/vim-epitech)
and clang-format 21 or newer; the install script or the `epitech-dump-arch`
installer sets those up. The Epitech updater does not update LazyVim itself.

The `lua/plugins/theme.lua` symlink follows the current Omarchy theme on an
Omarchy machine; it will not resolve on systems without that theme path.

`<leader>cf` formats C and Makefiles, `<leader>cH` inserts a filetype-aware
Epitech header, and `<leader>cG` adds an include guard to a C header.

At most 6 file buffers stay open, so the tab bar never shows more than 6 tabs:
opening another closes the least recently used one, except buffers with unsaved
changes, buffers shown in a window, and buffers pinned with
`:BufferLineTogglePin`. Change the limit with `M.max` in
`lua/config/buffer_limit.lua`.
