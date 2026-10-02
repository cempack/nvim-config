-- Managed by epitech-dump-arch. Re-run the installer to update this file.
local plugin_dir = vim.fn.stdpath("data") .. "/epitech-upgrade/nvim/epitech.nvim"

return {
  { import = "lazyvim.plugins.extras.lang.clangd" },
  {
    dir = plugin_dir,
    name = "epitech.nvim",
    lazy = false,
    init = function()
      vim.filetype.add({ extension = { h = "c" } })
    end,
    config = function()
      require("epitech").setup()
    end,
  },
  {
    "stevearc/conform.nvim",
    dependencies = { "epitech.nvim" },
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.c = { "epitech_vim" }
      opts.formatters_by_ft.make = { "bake" }
      opts.formatters = opts.formatters or {}
      opts.formatters.epitech_vim = require("epitech").formatter()
    end,
  },
}
