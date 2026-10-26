if vim.g.loaded_project_picker then return end
vim.g.loaded_project_picker = true

vim.api.nvim_create_user_command('Projects', function()
  require('project_picker').open()
end, { desc = 'Open the project folder picker' })
