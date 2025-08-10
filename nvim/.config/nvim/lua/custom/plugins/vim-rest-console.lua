-- vim-rest-console
-- https://github.com/diepm/vim-rest-console

return {
  'diepm/vim-rest-console',
  ft = 'http',
  init = function()
    -- Filetype detection

    vim.api.nvim_create_autocmd({ 'BufNewFile', 'BufRead', 'BufReadPost' }, {

      pattern = '*.http',

      callback = function()
        vim.bo.syntax = 'rest'
        vim.bo.filetype = 'rest'
      end,
    })

    -- Global settings

    vim.g.vrc_trigger = '<leader>vrc'
    vim.g.vrc_curl_opts = {
      ['-L'] = '',
      ['-i'] = '',
      ['-s'] = '',
      ['-k'] = '',
    }
  end,

  config = function()
    -- Buffer-local setting: set default response content type

    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'rest',
      callback = function()
        vim.b.vrc_response_default_content_type = 'application/json'
      end,
    })
  end,
}
