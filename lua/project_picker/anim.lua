-- Animations for the picker: the dashboard frames (lua/dashboard_frames_*.lua) or plain-text
-- ASCII animations from the configured anim_dir (files made by gif2ascii.py).
local Config = require('project_picker.config')
local U = require('project_picker.util')
local uv = vim.uv or vim.loop
local api = vim.api

local A = {}

local MIN_REDRAW_MS = 30
local ALPHA = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
local SIZES = { -- dashboard frame sets, biggest first: module, rows, columns
  { 'dashboard_frames_xl', 48, 82 },
  { 'dashboard_frames_full', 38, 65 },
  { 'dashboard_frames_half', 20, 35 },
}
local MIN_PICKER_WIDTH = 70 -- the picker needs this many columns next to the animation

-- External animations: plain .txt, no header; every frame has the same number of lines and the
-- next frame starts right after it.
local ext_cache = {}

function A.list()
  local out = {}
  local h = uv.fs_scandir(Config.opts.anim_dir)
  while h do
    local name, t = uv.fs_scandir_next(h)
    if not name then break end
    if t ~= 'directory' and name:lower():match('%.txt$') then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- The file does not say how tall a frame is. Guess it: the right height is the one where
-- consecutive frames line up (same characters at the same row/column).
local function detect_height(lines)
  local n = #lines
  local best, best_score = n, -1
  for h = 8, math.min(160, math.floor(n / 2)) do
    if n % h == 0 then
      local pairs_n = math.min(n / h - 1, 6)
      local same, total = 0, 0
      for f = 0, pairs_n - 1 do
        for r = 1, h, 2 do
          local a, b = lines[f * h + r], lines[(f + 1) * h + r]
          for c = 1, math.min(#a, #b), 3 do
            total = total + 1
            if a:byte(c) == b:byte(c) then same = same + 1 end
          end
        end
      end
      local score = total > 0 and same / total or 0
      if score > best_score + 1e-9 then best, best_score = h, score end
    end
  end
  return best
end

local function load_external(name)
  if ext_cache[name] ~= nil then return ext_cache[name] or nil end
  local ok, lines = pcall(vim.fn.readfile, Config.opts.anim_dir .. '/' .. name)
  if not ok or #lines == 0 then
    ext_cache[name] = false
    return nil
  end
  local h = detect_height(lines)
  local nf = math.floor(#lines / h)
  local cols = 0
  for _, l in ipairs(lines) do cols = math.max(cols, vim.fn.strdisplaywidth(l)) end
  local frames, times = {}, {}
  for f = 0, nf - 1 do
    frames[f + 1] = vim.list_slice(lines, f * h + 1, (f + 1) * h)
    times[f + 1] = f * 1000 / Config.opts.anim_fps
  end
  ext_cache[name] = {
    data = { frames = frames, times = times, duration = nf * 1000 / Config.opts.anim_fps },
    rows = h, cols = cols, speed = 1, plain = true,
  }
  return ext_cache[name]
end

local function fits(rows, cols)
  local W, H = U.screen()
  return H >= rows + 2 and W - 2 - (cols + 2) - 1 >= MIN_PICKER_WIDTH
end

-- `choice`: nil / 'builtin' for the dashboard frames, or the file name of an external
-- animation. Returns { data, rows, cols, plain?, speed? } or nil when nothing fits.
function A.pick(choice)
  if choice and choice ~= 'builtin' then
    local ext = load_external(choice)
    if ext and fits(ext.rows, ext.cols) then
      -- one color for the whole window: the window highlight does it, no per-line marks
      api.nvim_set_hl(0, 'PickerAnimBody', { fg = U.hl('Comment').fg, bg = U.hl('Normal').bg })
      return ext
    end
  end
  for _, s in ipairs(SIZES) do
    if fits(s[2], s[3]) then
      local ok, data = pcall(require, s[1])
      if ok and type(data) == 'table' and data.frames and data.palette then
        for i, color in ipairs(data.palette) do
          local name = 'DashAnim' .. (i - 1)
          if vim.tbl_isempty(api.nvim_get_hl(0, { name = name })) then
            api.nvim_set_hl(0, name, { fg = color })
          end
        end
        return { data = data, rows = s[2], cols = s[3] }
      end
    end
  end
end

-- window highlight mapping for an animation window
function A.winhl(anim)
  return (anim and anim.plain and 'NormalFloat:PickerAnimBody' or 'NormalFloat:Normal')
    .. ',FloatBorder:PickerBorder'
end

-- dashboard frame: rows of { characters, color classes } -> text lines + colored ranges
local function build_frame(frame)
  if type(frame[1]) == 'string' then return { lines = frame, marks = {} } end
  local lines, marks = {}, {}
  for r, row in ipairs(frame) do
    local chars = vim.fn.split(row[1], [[\zs]])
    local cls = row[2]
    local cur, start, buf = nil, 0, {}
    local function flush()
      if cur and #buf > 0 then
        local s = table.concat(buf)
        marks[#marks + 1] = { r - 1, start, start + #s, 'DashAnim' .. ((ALPHA:find(cur, 1, true) or 1) - 1) }
        start = start + #s
      end
      buf = {}
    end
    for i, ch in ipairs(chars) do
      local c = cls:sub(i, i)
      if c == ' ' then c = cur or '0' end
      if c ~= cur then
        flush()
        cur = c
      end
      buf[#buf + 1] = ch
    end
    flush()
    lines[r] = row[1]
  end
  return { lines = lines, marks = marks }
end

-- Play `anim` into `buf` until is_closed() or the returned stop function. The frame is chosen
-- by the clock (not by counting ticks), so playback speed stays constant under load.
function A.run(anim, buf, is_closed)
  local data = anim.data
  local times = data.times
  local duration = data.duration or (#data.frames * 100)
  local speed = anim.speed or Config.opts.anim_speed
  local cache, had_marks = {}, false
  local ns = api.nvim_create_namespace('project_picker_anim')
  local function frame_at(vt)
    if not times then return math.floor(vt / 100) % #data.frames + 1 end
    local lo, hi = 1, #times
    while lo < hi do
      local mid = math.floor((lo + hi + 1) / 2)
      if times[mid] <= vt then lo = mid else hi = mid - 1 end
    end
    return lo
  end
  local function draw(idx)
    local f = cache[idx]
    if not f then
      f = build_frame(data.frames[idx])
      cache[idx] = f
    end
    api.nvim_buf_set_lines(buf, 0, -1, false, f.lines)
    if #f.marks > 0 or had_marks then -- plain frames never have colored ranges: nothing to clear
      api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      had_marks = #f.marks > 0
    end
    for _, m in ipairs(f.marks) do
      pcall(api.nvim_buf_set_extmark, buf, ns, m[1], m[2], { end_col = m[3], hl_group = m[4] })
    end
  end

  local timer, stopped = uv.new_timer(), false
  local function stop()
    stopped = true
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end

  local t0, last, current = uv.hrtime(), 0, 1
  draw(1)
  timer:start(16, 16, vim.schedule_wrap(function()
    if stopped then return end
    if is_closed() or not api.nvim_buf_is_valid(buf) then return stop() end
    local now = uv.hrtime()
    local idx = frame_at(((now - t0) / 1e6 * speed) % duration)
    if idx ~= current and (now - last) / 1e6 >= MIN_REDRAW_MS then
      current, last = idx, now
      draw(idx)
    end
  end))
  return stop
end

return A
