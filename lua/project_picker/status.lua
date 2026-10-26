-- The editor's bottom statusline is hidden while the picker is open; the mode and a clock live
-- in the footer of the folder list instead.
local api = vim.api
local uv = vim.uv or vim.loop

local Status = {}

local MODE_NAMES = {
  n = 'NORMAL', i = 'INSERT', v = 'VISUAL', V = 'V-LINE', ['\22'] = 'V-BLOCK',
  R = 'REPLACE', c = 'COMMAND', s = 'SELECT', t = 'TERMINAL',
}

function Status.attach(P)
  local want_ls = vim.o.laststatus
  vim.o.laststatus = 0
  local group = api.nvim_create_augroup('ProjectPickerStatus', { clear = true })

  -- keep it hidden (lualine restores 'laststatus' after VeryLazy, other plugins may too)
  local function enforce()
    if P.closed then return end
    if vim.o.laststatus ~= 0 then
      want_ls = vim.o.laststatus
      vim.o.laststatus = 0
    end
  end

  function P.update_status()
    if P.closed or not api.nvim_win_is_valid(P.win_list) then return end
    local m = api.nvim_get_mode().mode:sub(1, 1)
    local label = MODE_NAMES[m] or m:upper()
    local mode_txt = ' ' .. (m == 'i' and ('<' .. label .. '>') or ('[' .. label .. ']'))
    local clock = os.date('%d.%m.%Y %H:%M') .. ' '
    -- same look as the info footer: border dashes stay visible on both sides of the text
    local total = api.nvim_win_get_width(P.win_list) - 6
    local pad = total - vim.fn.strdisplaywidth(mode_txt) - vim.fn.strdisplaywidth(clock)
    if pad < 1 then return end
    pcall(api.nvim_win_set_config, P.win_list, {
      footer = { { mode_txt .. string.rep(' ', pad) .. clock, 'PickerTitle' } },
      footer_pos = 'center',
    })
  end

  api.nvim_create_autocmd('OptionSet', { group = group, pattern = 'laststatus', callback = enforce })
  api.nvim_create_autocmd({ 'VimEnter', 'UIEnter', 'WinEnter', 'BufEnter' }, {
    group = group, callback = function() vim.schedule(enforce) end,
  })
  api.nvim_create_autocmd('User', { group = group, pattern = 'VeryLazy', callback = function() vim.schedule(enforce) end })
  api.nvim_create_autocmd('ModeChanged', { group = group, callback = function() vim.schedule(P.update_status) end })

  local timer = uv.new_timer()
  timer:start(1000, 1000, vim.schedule_wrap(function()
    if P.closed then
      if not timer:is_closing() then timer:stop() timer:close() end
      return
    end
    enforce()
    P.update_status()
  end))

  P.update_status()

  P.cleanup[#P.cleanup + 1] = function()
    pcall(api.nvim_del_augroup_by_id, group)
    if want_ls == 0 and vim.g.lualine_laststatus then want_ls = vim.g.lualine_laststatus end
    vim.o.laststatus = want_ls
  end
end

return Status
