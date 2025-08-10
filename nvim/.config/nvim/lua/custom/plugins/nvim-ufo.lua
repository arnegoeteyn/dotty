-- nvim-ufo
-- https://github.com/diepm/nvim-ufo

-- ufo configuration
vim.o.foldcolumn = '1' -- '0' is not bad
vim.o.foldlevel = 99 -- Using ufo provider need a large value, feel free to decrease the value
vim.o.foldlevelstart = 99
vim.o.foldenable = true

return {
  'kevinhwang91/nvim-ufo',
  lazy = false,
  dependencies = 'kevinhwang91/promise-async',
  opts = {
    provider_selector = function(bufnr, filetype, buftype)
      return { 'treesitter', 'indent' }
    end,
  },
  keys = {
    {
      'zR',
      function()
        require('ufo').openAllFolds()
      end,
    },
    {
      'zM',
      function()
        require('ufo').closeAllFolds()
      end,
    },
  },
}
