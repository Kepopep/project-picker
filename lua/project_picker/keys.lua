-- Buffer-local key mappings of the search line and the folder list.
local U = require('project_picker.util')
local api = vim.api

local Keys = {}

function Keys.attach(P)
  local IN, LIST = P.buf_in, P.buf_list
  local N, IN_MODES = { 'n' }, { 'i', 'n' }

  -- same key in the search line (insert + normal) and in the folder list (normal)
  local function both(keys, fn)
    U.map(IN, keys, fn, IN_MODES)
    U.map(LIST, keys, fn, N)
  end

  -- search line: insert / normal behave like plain nvim; only these keys are special
  U.map(IN, { '<Down>', '<C-n>', '<C-j>' }, P.focus_list, IN_MODES)
  U.map(IN, { 'j' }, P.focus_list, N)
  U.map(IN, { '<CR>' }, P.confirm, IN_MODES)
  U.map(IN, { '<C-c>', 'q' }, P.close, N)
  U.map(IN, { '<C-c>' }, P.close, { 'i' })
  U.map(IN, { '?' }, P.show_help, N) -- in insert mode ? is a normal character

  -- folder list: vim-style selection
  U.map(LIST, { 'j', '<Down>', '<C-n>' }, function() P.move(1) end, N)
  U.map(LIST, { 'k', '<Up>', '<C-p>' }, function()
    if P.sel <= 1 then P.focus_input(false) else P.move(-1) end
  end, N)
  U.map(LIST, { '<C-d>', '<PageDown>' }, function() P.move(10) end, N)
  U.map(LIST, { '<C-u>', '<PageUp>' }, function() P.move(-10) end, N)
  U.map(LIST, { 'l', '<Tab>', '<Right>' }, P.expand, N)
  U.map(LIST, { 'h', '<S-Tab>', '<Left>' }, P.collapse, N)
  U.map(LIST, { 'gg' }, function() P.jump(1) end, N)
  U.map(LIST, { 'G' }, function() P.jump(#P.items) end, N)
  U.map(LIST, { '<CR>' }, P.confirm, N)
  U.map(LIST, { 'q', '<C-c>' }, P.close, N)
  U.map(LIST, { 'i', 'a', 'A', 'I', 'o', 'O', 's', 'S', 'c', 'C', '/' }, function() P.focus_input(true) end, N)
  api.nvim_create_autocmd('InsertEnter', { buffer = LIST, callback = function() vim.cmd('stopinsert') end })

  -- folder actions (list only)
  U.map(LIST, { '.' }, P.toggle_hidden, N)
  U.map(LIST, { 'p' }, P.toggle_projects, N)
  U.map(LIST, { 'r' }, P.toggle_recent, N)
  U.map(LIST, { 'P' }, P.toggle_pin, N)
  U.map(LIST, { 'R' }, P.toggle_root, N)
  U.map(LIST, { 'x', '<Del>' }, P.remove_recent, N)
  U.map(LIST, { 'n' }, P.edit_note, N)
  U.map(LIST, { '?' }, P.show_help, N)

  -- available in both buffers
  both({ '<M-h>' }, P.toggle_hidden)
  both({ '<M-p>' }, P.toggle_projects)
  both({ '<M-r>' }, P.toggle_recent)
  both({ '<M-a>' }, function() P.cycle_anim() end)
  both({ '<F1>' }, P.show_help)
  for k = 1, 9 do
    both({ '<M-' .. k .. '>' }, function() P.open_pinned(k) end)
  end
end

return Keys
