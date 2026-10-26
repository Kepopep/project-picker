-- Mouse: global mappings while the picker is open (it is modal); the window under the mouse
-- comes from getmousepos().
local api = vim.api

local Mouse = {}

function Mouse.attach(P)
  local old_mouse = vim.o.mouse
  if old_mouse == '' then vim.o.mouse = 'a' end

  -- row, column inside `win` when the mouse is over it
  local function inside(win, m)
    if m.winid ~= win then return end
    return m.winrow - 1, m.wincol - 1
  end

  local function click_input(m)
    local _, c = inside(P.win_in, m)
    local line = api.nvim_buf_get_lines(P.buf_in, 0, 1, false)[1] or ''
    local last = #line - (api.nvim_get_mode().mode == 'i' and 0 or 1)
    if P.zone ~= 'input' then
      P.zone = 'input'
      P.select(P.sel)
      api.nvim_set_current_win(P.win_in)
      P.update_status()
    end
    pcall(api.nvim_win_set_cursor, P.win_in, { 1, math.min(math.max(c, 2), math.max(last, 2)) })
  end

  local function click_list(m, double)
    local i = m.line -- buffer line under the mouse
    if i < 1 or i > #P.items then return end
    if double then
      P.sel = i
      return P.confirm()
    end
    P.select(i)
    -- single click: toggle the folder open/closed (in search results: reveal it in the tree);
    -- pinned rows are only selected
    local n = P.items[i]
    if P.flat() or i > P.npin then
      if not P.flat() and n.expanded then P.collapse() else P.expand() end
    end
    P.switch_zone('list')
  end

  local function click(double)
    if P.closed then return end
    if P.win_help then return P.close_help() end
    local m = vim.fn.getmousepos()
    if inside(P.win_in, m) then return click_input(m) end
    if inside(P.win_list, m) then return click_list(m, double) end
  end

  local function wheel(dir)
    if P.closed or P.win_help then return end
    local m = vim.fn.getmousepos()
    if inside(P.win_prev, m) then
      pcall(api.nvim_win_call, P.win_prev, function()
        vim.cmd('normal! 3' .. (dir > 0 and '\5' or '\25'))
      end)
      return
    end
    if #P.items == 0 then return end
    local target = math.max(1, math.min(#P.items, P.sel + dir))
    if P.zone == 'list' then
      P.select(target)
    else
      P.sel = target
      P.switch_zone('list')
    end
  end

  local keys = {
    { '<LeftMouse>', function() click(false) end },
    { '<2-LeftMouse>', function() click(true) end },
    { '<ScrollWheelDown>', function() wheel(1) end },
    { '<ScrollWheelUp>', function() wheel(-1) end },
  }
  for _, k in ipairs(keys) do
    vim.keymap.set({ 'n', 'i' }, k[1], k[2], { silent = true, nowait = true })
  end
  P.cleanup[#P.cleanup + 1] = function()
    for _, k in ipairs(keys) do pcall(vim.keymap.del, { 'n', 'i' }, k[1]) end
    vim.o.mouse = old_mouse
  end
end

return Mouse
