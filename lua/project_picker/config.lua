-- Options. Defaults below; override with require('project_picker').setup({ ... }).
local C = {}

C.defaults = {
  -- folder with plain-text ASCII animations (*.txt made by gif2ascii.py); Alt-a cycles them
  anim_dir = vim.fn.stdpath('data') .. '/project-picker/animations',
  anim_fps = 20, -- playback rate of those .txt animations (the files carry no timing)
  anim_speed = 1.5, -- playback speed of the built-in dashboard frames
  recent_max = 30, -- how many recently opened folders are remembered
  crawl_depth = 4, -- background search index: how deep to read folders
  crawl_max = 30000, -- ... and how many folders at most
  store_file = vim.fn.stdpath('data') .. '/project-picker.json', -- pinned / recent / roots / notes
}

C.opts = vim.deepcopy(C.defaults)

function C.setup(opts)
  C.opts = vim.tbl_deep_extend('force', C.opts, opts or {})
end

return C
