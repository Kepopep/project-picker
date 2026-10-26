-- The picker itself: creates the state table P, the windows and the autocmds, and wires the
-- other modules (view, actions, keys, mouse, help, status, anim) to it.
local U = require('project_picker.util')
local Store = require('project_picker.store')
local Tree = require('project_picker.tree')
local Anim = require('project_picker.anim')
local Layout = require('project_picker.layout')
local api = vim.api
local uv = vim.uv or vim.loop

local M = {}

local WINHL = 'NormalFloat:Normal,FloatBorder:PickerBorder,FloatTitle:PickerTitle,FloatFooter:PickerTitle'
local CRAWL_SLICE = 60 -- folders read per background tick
local RESULTS_REFRESH_MS = 150 -- how often search results are refreshed while the crawl runs

-- floats use the editor background (Normal) instead of the lighter NormalFloat
local function set_float_hl()
  local bg = U.hl('Normal').bg
  local border = U.hl('FloatBorder').fg or U.hl('Comment').fg or U.hl('Normal').fg
  local title = U.hl('FloatTitle').fg or U.hl('Title').fg or U.hl('Normal').fg
  api.nvim_set_hl(0, 'PickerBorder', { fg = border, bg = bg })
  api.nvim_set_hl(0, 'PickerTitle', { fg = title, bg = bg, bold = true })
  api.nvim_set_hl(0, 'PickerSel', { link = 'Visual', default = true })
  api.nvim_set_hl(0, 'PickerCursor', { blend = 100, nocombine = true })
end

-- Startup only (nvim -S): the picker sits on top of the empty start buffer. Flag the buffer as
-- modified so the snacks dashboard does not open behind the picker, and hide its line number /
-- cursorline. Returns the function that undoes it.
local function hide_start_buffer(win)
  local buf = api.nvim_win_get_buf(win)
  local was_modified = vim.bo[buf].modified
  local options = { 'number', 'relativenumber', 'cursorline', 'signcolumn', 'statuscolumn', 'foldcolumn' }
  local saved = {}
  for _, o in ipairs(options) do saved[o] = vim.wo[win][o] end
  vim.bo[buf].modified = true
  vim.wo[win].number, vim.wo[win].relativenumber, vim.wo[win].cursorline = false, false, false
  vim.wo[win].signcolumn, vim.wo[win].statuscolumn, vim.wo[win].foldcolumn = 'no', '', '0'
  return function()
    if api.nvim_buf_is_valid(buf) then vim.bo[buf].modified = was_modified end
    if api.nvim_win_is_valid(win) then
      for o, v in pairs(saved) do pcall(function() vim.wo[win][o] = v end) end
    end
  end
end

local function scratch_buf()
  local b = api.nvim_create_buf(false, true)
  vim.bo[b].bufhidden = 'wipe'
  vim.bo[b].swapfile = false
  return b
end

local function build()
  local store = Store.load()
  local P = {
    tree = Tree.new(), store = store,
    ns = api.nvim_create_namespace('project_picker'),
    query = '', items = {}, sel = 1, zone = 'input', closed = false,
    npin = 0, proot = {}, rtag = {}, tagid = {}, numid = {},
    project_only = false,
    -- start on the "recent" view when there is anything to show there
    recent_only = #store.recent > 0 or #store.pinned > 0 or #store.roots > 0,
    cleanup = {}, prev_win = api.nvim_get_current_win(), swapping_anim = false,
  }
  if vim.v.vim_did_enter == 0 then P.cleanup[#P.cleanup + 1] = hide_start_buffer(P.prev_win) end

  P.buf_in, P.buf_list, P.buf_prev = scratch_buf(), scratch_buf(), scratch_buf()
  vim.bo[P.buf_in].buftype = 'prompt'
  vim.fn.prompt_setprompt(P.buf_in, '> ')
  set_float_hl()

  -- windows: search line, folder list, info panel, optional animation
  local cfg
  P.anim_choice = store.anim or 'builtin' -- 'builtin' or the file name of an external animation
  cfg, P.anim = Layout.compute(Anim.pick(P.anim_choice))
  local wopts = Layout.wopts
  P.win_in = api.nvim_open_win(P.buf_in, true, wopts(cfg.input, ' Select project folder '))
  P.win_list = api.nvim_open_win(P.buf_list, false, wopts(cfg.list, ' Folders ', { focusable = true }))
  P.win_prev = api.nvim_open_win(P.buf_prev, false, wopts(cfg.prev, ' Info ', { focusable = true }))
  for _, w in ipairs({ P.win_in, P.win_prev }) do vim.wo[w].winhl = WINHL end
  -- the selection is drawn by an extmark so it also covers the end-of-line tags
  vim.wo[P.win_list].winhl = WINHL .. ',CursorLine:PickerSel'
  vim.wo[P.win_list].cursorline = false
  vim.wo[P.win_list].wrap, vim.wo[P.win_prev].wrap = false, false

  local function open_anim_win(a, acfg)
    local buf = scratch_buf()
    P.win_anim = api.nvim_open_win(buf, false, vim.tbl_extend('force', acfg, {
      style = 'minimal', border = 'rounded', focusable = false,
    }))
    vim.wo[P.win_anim].winhl = Anim.winhl(a)
    P.anim_stop = Anim.run(a, buf, function() return P.closed end)
  end
  if cfg.anim then open_anim_win(P.anim, cfg.anim) end

  -- feature modules
  require('project_picker.view').attach(P)
  require('project_picker.actions').attach(P)
  require('project_picker.help').attach(P)
  require('project_picker.status').attach(P)

  function P.close()
    if P.closed then return end
    P.closed = true
    M.active = false
    for _, f in ipairs(P.cleanup) do pcall(f) end
    vim.cmd('stopinsert')
    -- (win_anim / win_help may be nil, so a table of explicit values and pairs, not ipairs)
    for _, w in pairs({ P.win_in, P.win_list, P.win_prev, P.win_anim or false, P.win_help or false }) do
      if w and api.nvim_win_is_valid(w) then pcall(api.nvim_win_close, w, true) end
    end
    if api.nvim_win_is_valid(P.prev_win) then pcall(api.nvim_set_current_win, P.prev_win) end
  end

  require('project_picker.keys').attach(P)
  require('project_picker.mouse').attach(P)

  -- hide the terminal cursor while the list has focus (the row highlight shows the selection),
  -- otherwise the first character of the selected row gets a different color
  local orig_cursor = vim.o.guicursor
  api.nvim_create_autocmd('BufEnter', { buffer = P.buf_list, callback = function() vim.o.guicursor = 'a:PickerCursor' end })
  api.nvim_create_autocmd('BufLeave', { buffer = P.buf_list, callback = function() vim.o.guicursor = orig_cursor end })
  P.cleanup[#P.cleanup + 1] = function() vim.o.guicursor = orig_cursor end

  api.nvim_create_autocmd('ColorScheme', {
    callback = function()
      if P.closed then return true end
      set_float_hl()
      P.sel_groups = {}
    end,
  })

  api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    buffer = P.buf_in,
    callback = function()
      local q = P.cur_query()
      if q == P.query then return end
      P.query = q
      P.rebuild()
    end,
  })

  -- :q (or any other way of closing) on one picker window closes the whole picker
  local function watch_closed(w)
    api.nvim_create_autocmd('WinClosed', {
      pattern = tostring(w),
      once = true,
      callback = function()
        if P.swapping_anim then return end
        vim.schedule(P.close)
      end,
    })
  end
  for _, w in ipairs({ P.win_in, P.win_list, P.win_prev, P.win_anim }) do watch_closed(w) end

  -- focus left the picker (e.g. a mouse click elsewhere): close it
  local function is_picker_win(w)
    return w == P.win_in or w == P.win_list or w == P.win_prev or w == P.win_anim
  end
  api.nvim_create_autocmd('WinEnter', {
    callback = function()
      if P.closed then return true end
      if is_picker_win(api.nvim_get_current_win()) then return end
      -- re-check later: windows opened by the picker itself (help) are only known once
      -- nvim_open_win has returned
      vim.schedule(function()
        if P.closed then return end
        local now = api.nvim_get_current_win()
        if not is_picker_win(now) and now ~= P.win_help then P.close() end
      end)
    end,
  })

  -- geometry follows the terminal size
  local function relayout()
    local c, used = Layout.compute(P.anim)
    P.anim = used
    api.nvim_win_set_config(P.win_in, c.input)
    api.nvim_win_set_config(P.win_list, c.list)
    api.nvim_win_set_config(P.win_prev, c.prev)
    return c
  end
  api.nvim_create_autocmd('VimResized', {
    callback = function()
      if P.closed then return true end
      local c = relayout()
      if P.win_anim and c.anim then api.nvim_win_set_config(P.win_anim, c.anim) end
      vim.schedule(P.update_status)
    end,
  })

  -- swap the animation window for another animation (the picker is laid out around it)
  function P.set_anim(choice)
    P.swapping_anim = true
    if P.anim_stop then P.anim_stop() P.anim_stop = nil end
    if P.win_anim and api.nvim_win_is_valid(P.win_anim) then pcall(api.nvim_win_close, P.win_anim, true) end
    P.win_anim = nil
    P.anim_choice = choice
    store.anim = choice ~= 'builtin' and choice or nil
    Store.save(store)
    P.anim = Anim.pick(choice)
    local c = relayout()
    if P.anim and c.anim then
      open_anim_win(P.anim, c.anim)
      watch_closed(P.win_anim)
    end
    P.swapping_anim = false
    local shown = P.anim and (P.anim.plain and choice or 'builtin') or 'none (window too small)'
    if choice ~= 'builtin' and shown ~= choice then
      vim.notify('Animation ' .. choice .. ' does not fit this window, showing: ' .. shown)
    else
      vim.notify('Animation: ' .. shown)
    end
    vim.schedule(P.update_status)
  end

  function P.cycle_anim()
    local names = { 'builtin' }
    vim.list_extend(names, Anim.list())
    local cur = 1
    for i, n in ipairs(names) do
      if n == P.anim_choice then cur = i end
    end
    P.set_anim(names[cur % #names + 1])
  end

  P.tree:fetch_drive_labels(function()
    if not P.closed then P.render() end
  end)
  P.rebuild()
  P.update_title()
  vim.cmd('startinsert')

  -- background crawl so search finds folders that were never expanded; results are refreshed
  -- at most every RESULTS_REFRESH_MS
  local dirty, last_refresh = false, 0
  local function tick()
    if P.closed then return end
    local searching = P.query ~= '' or P.project_only
    if P.tree:crawl_step(CRAWL_SLICE) and searching then dirty = true end
    local pending = P.tree:crawl_pending()
    if dirty and (not pending or uv.now() - last_refresh >= RESULTS_REFRESH_MS) then
      dirty, last_refresh = false, uv.now()
      P.rebuild(P.items[P.sel])
    end
    if pending then vim.defer_fn(tick, 10) end
  end
  vim.defer_fn(tick, 50)

  return P
end

function M.open()
  if M.active then return end
  M.active = true
  local ok, res = xpcall(build, debug.traceback)
  if ok then
    M.current = res
  else
    M.active = false
    vim.notify('Projects: ' .. tostring(res), vim.log.levels.ERROR)
  end
end

return M
