-- ?: popup listing all keys. q / <Esc> / ? / <CR> / :q closes it and focus returns to the picker.
local api = vim.api

local Help = {}

local KEYS = {
  { 'Search line' },
  { '<Esc>', 'leave insert mode (normal nvim editing, hjkl move the caret)' },
  { 'j  <Down>', 'go to the folder list' },
  { '<CR>', 'open the selected folder' },
  { 'q  <C-c>', 'close the picker (also :q anywhere)' },
  { 'Folder list' },
  { 'j k  <Up> <Down>', 'move the selection (k on the first row: back to search)' },
  { 'h  l  <Tab>', 'collapse / expand folder' },
  { 'gg  G', 'first / last row' },
  { '<C-d>  <C-u>', 'page down / up' },
  { '<CR>', 'open the folder (cd + file explorer)' },
  { 'i  a  /', 'back to the search line' },
  { 'Views' },
  { '.   <M-h>', 'show / hide hidden and system folders' },
  { 'p   <M-p>', 'only projects (.git, package.json, .sln, ...)' },
  { 'r   <M-r>', 'recent view: pinned, roots, recent' },
  { 'Folder actions' },
  { 'P', 'pin / unpin' },
  { 'R', 'mark / unmark as root (its sub-folders are listed)' },
  { 'x  <Del>', 'forget in the recent list' },
  { 'n', 'edit the note (shown in the list, searchable)' },
  { '<M-1> .. <M-9>', 'open the 1st .. 9th pinned folder' },
  { '<M-a>', 'next animation (built-in, then *.txt from the animation folder)' },
  { 'Mouse' },
  { 'click', 'expand / collapse the folder' },
  { 'double click', 'open the folder' },
  { 'wheel', 'move the selection / scroll the info panel' },
}

local WINHL = 'NormalFloat:Normal,FloatBorder:PickerBorder,FloatTitle:PickerTitle,FloatFooter:PickerTitle'

function Help.attach(P)
  function P.close_help()
    if P.win_help and api.nvim_win_is_valid(P.win_help) then pcall(api.nvim_win_close, P.win_help, true) end
    P.win_help = nil
    local back = P.help_return
    P.help_return = nil
    if back and api.nvim_win_is_valid(back) and not P.closed then api.nvim_set_current_win(back) end
  end

  function P.show_help()
    if P.win_help then return P.close_help() end
    local lines, headers, width = {}, {}, 0
    for _, e in ipairs(KEYS) do
      if e[2] then
        lines[#lines + 1] = ('  %-18s %s'):format(e[1], e[2])
      else
        if #lines > 0 then lines[#lines + 1] = '' end
        lines[#lines + 1] = ' ' .. e[1]
        headers[#headers + 1] = #lines - 1
      end
    end
    for _, l in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(l)) end
    local W, H = vim.o.columns, vim.o.lines - vim.o.cmdheight
    width = math.min(width + 2, W - 4)
    local height = math.min(#lines, H - 4)
    local buf = api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    for _, r in ipairs(headers) do
      api.nvim_buf_set_extmark(buf, P.ns, r, 0, { line_hl_group = 'Special' })
    end
    P.help_return = api.nvim_get_current_win()
    P.win_help = api.nvim_open_win(buf, true, {
      relative = 'editor', style = 'minimal', border = 'rounded', zindex = 100,
      title = ' Keys ', title_pos = 'center',
      footer = ' q / <Esc> / ? close ', footer_pos = 'center',
      width = width, height = height,
      row = math.floor((H - height - 2) / 2), col = math.floor((W - width - 2) / 2),
    })
    vim.wo[P.win_help].winhl = WINHL
    for _, k in ipairs({ 'q', '<Esc>', '?', '<CR>', '<C-c>', '<F1>' }) do
      vim.keymap.set('n', k, P.close_help, { buffer = buf, nowait = true, silent = true })
    end
    -- closed by any means (:q included): forget it and give focus back to the picker
    api.nvim_create_autocmd('WinClosed', {
      pattern = tostring(P.win_help),
      once = true,
      callback = function()
        local back = P.help_return
        P.win_help, P.help_return = nil, nil
        vim.schedule(function()
          if back and not P.closed and api.nvim_win_is_valid(back) then api.nvim_set_current_win(back) end
        end)
      end,
    })
  end
end

return Help
