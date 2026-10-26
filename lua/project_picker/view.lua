-- What the list shows (build_items: tree / pinned zone / recent / search) and how it is drawn
-- (render: everything, select: only the selection moved). Attaches its functions to the picker
-- state table P.
local U = require('project_picker.util')
local Store = require('project_picker.store')
local Fuzzy = require('project_picker.fuzzy')
local Project = require('project_picker.project')
local api = vim.api
local uv = vim.uv or vim.loop

local View = {}

local PIN = '\u{f08d}' -- nerd font thumb-tack icon marking pinned folders
local ROOT = '\u{f0e8}' -- nerd font sitemap icon marking root folders
local GIT = '\u{e702}'
local PENCIL = '\u{f040}'
local INFO_TTL_MS = 2000

function View.attach(P)
  local tree, store, ns = P.tree, P.store, P.ns
  local info_cache, info_shown = {}, nil

  -- flat list (search results / projects / recent) instead of the tree
  function P.flat()
    return P.query ~= '' or P.project_only or P.recent_only
  end

  -- ---- what to show --------------------------------------------------------------------

  -- recent view: pinned, then per root (the root, its sub-folders, recent ones inside), then
  -- everything else recently opened (newest first)
  local function build_recent()
    P.rtag = {}
    local out, seen, rtime = {}, {}, {}
    for _, e in ipairs(store.recent) do rtime[U.key(e.path)] = e.time or 0 end
    -- label: when it was opened last, else the fallback text
    local function add(path, fallback)
      local n = tree:find(path)
      if not n or seen[n] or not tree:vis(n) then return end
      seen[n] = true
      local t = rtime[n.key]
      local text = t and Store.ago(t) or fallback
      if text then P.rtag[n] = { text, 'Comment' } end
      out[#out + 1] = n
    end
    for _, p in ipairs(store.pinned) do add(p) end -- pinned folders get a pin icon in every view
    P.npin = #out
    for i = 1, P.npin do P.proot[i] = i end -- Alt-<number> numbering
    for _, r in ipairs(store.roots) do
      r = U.norm(r)
      local rn = tree:find(r)
      if rn then
        add(r)
        tree:load(rn)
        for _, c in ipairs(rn.children) do add(c.path, 'in ' .. rn.name) end
        local prefix = r:lower():gsub('/$', '') .. '/'
        for _, e in ipairs(store.recent) do
          if U.key(e.path):sub(1, #prefix) == prefix then add(e.path) end
        end
      end
    end
    for _, e in ipairs(store.recent) do add(e.path) end
    return out
  end

  -- pinned folders on top (flat rows), then the whole tree
  local function build_tree()
    local items, seen = {}, {}
    for _, p in ipairs(store.pinned) do
      local n = tree:find(p)
      if n and not seen[n] and tree:vis(n) then
        seen[n] = true
        items[#items + 1] = n
        P.proot[#items] = #items
      end
    end
    P.npin = #items
    return tree:flatten(nil, items)
  end

  local function build_search()
    local items = {}
    local q = P.query:gsub('\\', '/')
    -- a typed path that exists goes first
    if q ~= '' and q:find('[/:]') then
      local st = uv.fs_stat(q)
      if st and st.type == 'directory' then
        local n = tree:find(q)
        if n then items[1] = n end
      end
    end
    local first = items[1]
    local hits = Fuzzy.search(tree.all, Fuzzy.tokens(q), {
      notes = store.notes,
      limit = 300,
      accept = function(n)
        return n ~= first and tree:vis(n) and (not P.project_only or tree:is_project(n))
      end,
    })
    vim.list_extend(items, hits)
    return items
  end

  function P.build_items()
    P.proot, P.npin = {}, 0 -- npin: pinned rows at the top (followed by a separator)
    if P.recent_only and P.query == '' then
      P.items = build_recent() -- typing a query searches everything instead
    elseif not P.flat() then
      P.items = build_tree()
    else
      P.items = build_search()
    end
  end

  -- ---- info panel -----------------------------------------------------------------------

  local function info_for(n)
    local note = store.notes[n.key]
    local c = info_cache[n.path]
    local now = uv.now()
    if c and c.note == note and now - c.t < INFO_TTL_MS then return c.lines end
    if vim.tbl_count(info_cache) > 60 then info_cache = {} end
    local lines = Project.info_lines(n.path, note)
    info_cache[n.path] = { note = note, t = now, lines = lines }
    return lines
  end

  function P.show_info()
    local n = P.items[P.sel]
    local info = n and info_for(n) or false
    if info == info_shown then return end -- same content already on screen
    info_shown = info
    local lines, hls = {}, {}
    if not info then
      lines = { 'No folder selected' }
    else
      for i, e in ipairs(info) do
        lines[i] = e[1]
        if e[2] then hls[#hls + 1] = { i - 1, e[2] } end
      end
    end
    api.nvim_buf_set_lines(P.buf_prev, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(P.buf_prev, ns, 0, -1)
    for _, h in ipairs(hls) do
      api.nvim_buf_set_extmark(P.buf_prev, ns, h[1], 0, { line_hl_group = h[2] })
    end
  end

  -- ---- drawing --------------------------------------------------------------------------

  -- highlight group with the selection background but the foreground of `name`
  -- (virtual text is not covered by the row highlight)
  P.sel_groups = {}
  local function sel_group(name)
    local g = P.sel_groups[name]
    if not g then
      g = 'PickerSelTag_' .. name
      api.nvim_set_hl(0, g, { fg = U.hl(name).fg, bg = U.hl('PickerSel').bg })
      P.sel_groups[name] = g
    end
    return g
  end

  local function del_mark(buf, id)
    if id then pcall(api.nvim_buf_del_extmark, buf, ns, id) end
  end

  -- (re)draw the end-of-line tags and the pin number of row i
  local function draw_tags(i)
    local n = P.items[i]
    if not n then return end
    local key = n.key
    local pinned = Store.is_pinned(store, key)
    local note = store.notes[key]
    local rtag = P.recent_only and P.query == '' and P.rtag[n]
    local project = tree:is_project(n)
    if not (project or pinned or note or rtag) then
      del_mark(P.buf_list, P.tagid[i])
      del_mark(P.buf_list, P.numid[i])
      P.tagid[i], P.numid[i] = nil, nil
      return
    end
    local on = P.zone == 'list' and i == P.sel
    local function hl(name) return on and sel_group(name) or name end
    local chunks = {}
    if on then chunks[1] = { ' ', 'PickerSel' } end
    if rtag then chunks[#chunks + 1] = { '  ' .. rtag[1], hl(rtag[2]) } end
    if n.git then chunks[#chunks + 1] = { '  ' .. GIT, hl('DiagnosticOk') } end
    if n.kinds and #n.kinds > 0 then
      chunks[#chunks + 1] = { (n.git and ' ' or '  ') .. table.concat(n.kinds, ' '), hl('Special') }
    end
    -- readable project name (package.json / .sln / ...) when it differs from the folder name
    if project or pinned then
      local lab = Project.label(n.path)
      if lab and lab:lower() ~= n.lname then
        chunks[#chunks + 1] = { '  \u{ab}' .. lab .. '\u{bb}', hl('String') }
      end
    end
    if note then
      chunks[#chunks + 1] = { '  ' .. PENCIL .. ' ' .. (#note > 40 and note:sub(1, 40) .. '…' or note), hl('Comment') }
    end
    P.tagid[i] = api.nvim_buf_set_extmark(P.buf_list, ns, i - 1, 0, {
      id = P.tagid[i], virt_text = chunks, virt_text_pos = 'eol',
    })
    -- number of the pinned row: Alt-<number> opens it
    local num = P.proot[i]
    if num and num <= 9 then
      P.numid[i] = api.nvim_buf_set_extmark(P.buf_list, ns, i - 1, 0, {
        id = P.numid[i], virt_text = { { num .. ' ', hl('Comment') } }, virt_text_pos = 'inline',
      })
    end
  end

  local function draw_selection_mark()
    if P.zone == 'list' and #P.items > 0 then
      P.selid = api.nvim_buf_set_extmark(P.buf_list, ns, P.sel - 1, 0, {
        id = P.selid, line_hl_group = 'PickerSel', priority = 10,
      })
    else
      del_mark(P.buf_list, P.selid)
      P.selid = nil
    end
  end

  local function draw_counter()
    api.nvim_buf_clear_namespace(P.buf_in, ns, 0, -1)
    api.nvim_buf_set_extmark(P.buf_in, ns, 0, 0, {
      virt_text = { { ('%d/%d'):format(#P.items > 0 and P.sel or 0, #P.items), 'Comment' } },
      virt_text_pos = 'right_align',
    })
  end

  -- Everything: rows, icons, separator, tags, selection. Use after the items changed.
  function P.render()
    if P.closed then return end
    local items, flat = P.items, P.flat()
    P.sel = math.max(1, math.min(P.sel, #items))
    local lines, icons = {}, {}
    for i, n in ipairs(items) do
      local head, name = '', n.path
      if not flat and i > P.npin then -- tree row: indent + fold arrow + name
        local arrow = n.loaded and tree:visible_count(n) == 0 and '  ' or (n.expanded and '▾ ' or '▸ ')
        head, name = string.rep('  ', n.depth) .. arrow, n.label or n.name
      end
      -- icons before the name: pin for pinned folders, sitemap for root folders
      local prefix, col = '', #head
      local function icon(glyph, group)
        icons[#icons + 1] = { i - 1, col, col + #glyph, group }
        col = col + #glyph + 1
        prefix = prefix .. glyph .. ' '
      end
      if Store.is_pinned(store, n.key) then icon(PIN, 'DiagnosticWarn') end
      if Store.is_root(store, n.key) then icon(ROOT, 'DiagnosticHint') end
      lines[i] = head .. prefix .. name
    end
    api.nvim_buf_set_lines(P.buf_list, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(P.buf_list, ns, 0, -1)
    P.tagid, P.numid, P.selid = {}, {}, nil
    for _, ic in ipairs(icons) do
      api.nvim_buf_set_extmark(P.buf_list, ns, ic[1], ic[2], { end_col = ic[3], hl_group = ic[4], priority = 20 })
    end
    -- separator between the pinned zone and the other folders (no pinned folders: no separator)
    if P.npin > 0 and P.npin < #items then
      api.nvim_buf_set_extmark(P.buf_list, ns, P.npin, 0, {
        virt_lines = { { { string.rep('─', api.nvim_win_get_width(P.win_list)), 'Comment' } } },
        virt_lines_above = true,
      })
    end
    for i = 1, #items do draw_tags(i) end
    if #items > 0 then api.nvim_win_set_cursor(P.win_list, { P.sel, 0 }) end
    draw_selection_mark()
    draw_counter()
    P.show_info()
  end

  -- Only the selection (or the focus zone) changed: move the highlight, redraw two rows.
  function P.select(i)
    if P.closed then return end
    local old = P.sel
    P.sel = math.max(1, math.min(i, #P.items))
    if #P.items > 0 then api.nvim_win_set_cursor(P.win_list, { P.sel, 0 }) end
    draw_selection_mark()
    if old ~= P.sel then draw_tags(old) end
    draw_tags(P.sel)
    draw_counter()
    P.show_info()
  end

  -- Rebuild the items and select `keep` (a node) again. A folder can be listed twice (pinned
  -- zone and tree): stay in the part the selection was in, otherwise expanding a pinned folder
  -- in the tree would jump the cursor up to its pinned copy.
  function P.rebuild(keep)
    local was_tree = not P.flat() and P.sel > P.npin
    P.build_items()
    P.sel = 1
    if keep then
      for i = (was_tree and P.npin or 0) + 1, #P.items do
        if P.items[i] == keep then P.sel = i break end
      end
    end
    P.render()
  end

  function P.cur_query()
    local line = api.nvim_buf_get_lines(P.buf_in, 0, 1, false)[1] or ''
    return (line:sub(3):gsub('^%s+', ''))
  end
end

return View
