-- Public API of project-picker.
--   require('project_picker').setup(opts)   optional, see config.lua for the options
--   require('project_picker').open()        the :Projects command calls this
local M = {}

function M.setup(opts)
  require('project_picker.config').setup(opts)
end

function M.open()
  require('project_picker.picker').open()
end

function M.close()
  local p = require('project_picker.picker').current
  if p then p.close() end
end

return M
