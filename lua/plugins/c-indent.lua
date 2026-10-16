-- Epitech C-L2 indents case labels inside a switch and their statements one
-- level further. Vim's cindent does that while typing; treesitter indent leaves
-- the line after a case label at the label's level.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { indent = { disable = { "c" } } },
  },
}
