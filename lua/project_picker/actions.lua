-- Everything the user can do in the picker: moving, folding, view toggles, pin / root / note /
-- forget, switching the focus zone, opening a folder. Attaches the functions to the picker
-- state table P.
local Store = require('project_picker.store')
local api = vim.api

local Actions = {}

function Actions.attach(P)
  local tree, store = P.tree, P.store

  function P.update_title()
    local t = ' Folders'
    if P.recent_only then t = t .. ' [recent]' end
    if P.project_only then t = t .. ' [projects]' end
    if tree.show_hidden then t = t .. ' (+ hidden)' end
    pcall(api.nvim_win_set_config, P.win_list, { title = t .. ' ', title_pos = 'center' })
  end

  -- ---- selection ------------------------------------------------------------------------

  function P.move(d)
    local n = #P.items
    if n > 0 then P.select((P.sel - 1 + d) % n + 1) end -- wraps around
  end

  function P.jump(i)
    if #P.items > 0 then P.select(i) end
  end

  -- Rebuild the items but keep the cursor on the same row number (a row was removed / changed).
  local function rebuild_keep_row()
    local at = P.sel
    P.rebuild()
    P.sel = math.min(at, math.max(#P.items, 1))
    P.render()
  end

  -- ---- tree folding ---------------------------------------------------------------------

  function P.expand()
    local n = P.items[P.sel]
    if not n then return end
    local flat = P.flat()
    if not flat and P.sel <= P.npin then return end -- pinned rows are not expandable
    if flat then
      -- reveal in the tree
      local p = n.parent
      while p do p.expanded = true p = p.parent end
      tree:load(n)
      n.expanded = true
      P.query, P.project_only, P.recent_only = '', false, false
      P.update_title()
      api.nvim_buf_set_lines(P.buf_in, 0, 1, false, { '> ' })
      return P.rebuild(n)
    end
    tree:load(n)
    n.expanded = tree:visible_count(n) > 0
    P.rebuild(n)
  end

  function P.collapse()
    local n = P.items[P.sel]
    if not n or P.flat() or P.sel <= P.npin then return end
    if n.expanded then
      n.expanded = false
      P.rebuild(n)
    elseif n.parent then
      P.rebuild(n.parent)
    end
  end

  -- ---- views ----------------------------------------------------------------------------

  function P.toggle_hidden()
    tree.show_hidden = not tree.show_hidden
    local keep = P.items[P.sel]
    while keep and not tree:vis(keep) do keep = keep.parent end
    P.rebuild(keep)
    P.update_title()
  end

  -- only folders detected as projects (.git, package.json, *.sln, ...) as a flat searchable list
  function P.toggle_projects()
    P.project_only = not P.project_only
    if P.project_only then P.recent_only = false end
    P.rebuild(P.items[P.sel])
    P.update_title()
  end

  -- recent / pinned / root folders as a flat list
  function P.toggle_recent()
    P.recent_only = not P.recent_only
    if P.recent_only then P.project_only = false end
    P.rebuild(P.items[P.sel])
    P.update_title()
  end

  -- ---- folder data ----------------------------------------------------------------------

  -- add / remove the selected folder in store[list] ('pinned' or 'roots')
  local function toggle_membership(list, added, removed)
    local n = P.items[P.sel]
    if not n then return end
    local on = Store.toggle(store, list, n.path)
    Store.save(store)
    vim.notify((on and added or removed) .. n.path)
    P.rebuild(n)
  end
  function P.toggle_pin() toggle_membership('pinned', 'Pinned: ', 'Unpinned: ') end
  function P.toggle_root()
    toggle_membership('roots', 'Root added (its sub-folders show in recent): ', 'Root removed: ')
  end

  -- forget the selected folder in the recent list (pins and roots are not touched)
  function P.remove_recent()
    local n = P.items[P.sel]
    if not n then return end
    if Store.forget(store, n.path) then
      Store.save(store)
      vim.notify('Removed from recent: ' .. n.path)
      rebuild_keep_row()
    else
      vim.notify('Not in the recent list: ' .. n.path)
    end
  end

  -- edit the note of the selected folder (shown in the list and the info panel, searchable)
  function P.edit_note()
    local n = P.items[P.sel]
    if not n then return end
    local cancel_mark = '\1'
    local text = vim.fn.input({ prompt = 'Note: ', default = store.notes[n.key] or '', cancelreturn = cancel_mark })
    if text == cancel_mark then return end
    text = vim.trim(text)
    store.notes[n.key] = text ~= '' and text or nil
    Store.save(store)
    P.rebuild(n)
  end

  -- ---- focus zones: real window focus. input = search line (plain nvim editing), list = folders

  -- Make `zone` ('input' / 'list') the active one and focus its window. The switch is deferred
  -- to the main loop so it also works from an insert-mode mapping.
  function P.switch_zone(zone)
    P.zone = zone
    vim.cmd('stopinsert')
    vim.schedule(function()
      if P.closed then return end
      api.nvim_set_current_win(zone == 'list' and P.win_list or P.win_in)
      P.select(P.sel)
      P.update_status()
    end)
  end

  function P.focus_list()
    if #P.items > 0 then P.switch_zone('list') end
  end

  function P.focus_input(insert)
    P.zone = 'input'
    P.select(P.sel) -- hides the selection highlight
    api.nvim_set_current_win(P.win_in)
    if insert then
      vim.cmd('startinsert!')
    else
      vim.cmd('stopinsert')
      -- caret lands on the text, not on the prompt
      local line = api.nvim_buf_get_lines(P.buf_in, 0, 1, false)[1] or ''
      pcall(api.nvim_win_set_cursor, P.win_in, { 1, math.max(#line - 1, 2) })
    end
    P.update_status()
  end

  -- ---- opening a folder -----------------------------------------------------------------

  -- an ordinary editing window: not a float, a real buffer, not a snacks (explorer) window
  local function ordinary(w)
    if not api.nvim_win_is_valid(w) or api.nvim_win_get_config(w).relative ~= '' then return false end
    local b = api.nvim_win_get_buf(w)
    return vim.bo[b].buftype == '' and not vim.bo[b].filetype:find('^snacks')
  end

  local function ordinary_window()
    for _, w in ipairs({ P.prev_win, api.nvim_get_current_win() }) do
      if ordinary(w) then return w end
    end
    for _, w in ipairs(api.nvim_list_wins()) do
      if ordinary(w) then return w end
    end
  end

  function P.open_path(path)
    Store.record(store, path)
    P.close()
    vim.cmd.cd(vim.fn.fnameescape(path))
    -- snacks explorer: `edit .` on a directory *toggles* the explorer, so when one is already
    -- open it would be closed. It re-reads the folder itself on DirChanged (a second set_cwd /
    -- find made the tree appear twice), so only move the focus to it.
    local S = rawget(_G, 'Snacks')
    local ok_get, explorers = pcall(function()
      return S and S.picker and S.picker.get({ source = 'explorer' }) or {}
    end)
    if ok_get and #explorers > 0 and pcall(function() explorers[1]:focus('list') end) then return end
    -- mid-session (:Projects) focus may sit in a special window (explorer sidebar, terminal, ...):
    -- run `edit .` in an ordinary window instead, otherwise it replaces that window's buffer
    local target = ordinary_window()
    if target then api.nvim_set_current_win(target) else vim.cmd('rightbelow vnew') end
    -- the current buffer may have unsaved changes
    local ok, err = pcall(vim.cmd, 'edit .')
    if not ok then
      vim.notify('Project folder is now ' .. path .. ' but could not open it: ' .. tostring(err), vim.log.levels.WARN)
    end
  end

  function P.confirm()
    local n = P.items[P.sel]
    if n then P.open_path(n.path) end
  end

  -- Alt-1..Alt-9: open the Nth pinned folder directly, the selection stays where it is
  function P.open_pinned(k)
    local seen, count = {}, 0
    for _, p in ipairs(store.pinned) do
      local n = tree:find(p)
      if n and not seen[n] and tree:vis(n) then
        seen[n] = true
        count = count + 1
        if count == k then return P.open_path(n.path) end
      end
    end
    vim.notify('No pinned folder #' .. k)
  end
end

return Actions
