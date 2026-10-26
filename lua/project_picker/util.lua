-- Small shared helpers: paths, file reading, one-pass folder scan, highlight lookup.
local uv = vim.uv or vim.loop
local api = vim.api

local U = {}

function U.join(a, b)
  if a:sub(-1) == '/' then return a .. b end
  return a .. '/' .. b
end

-- forward slashes, no trailing slash (except a drive root "C:/")
function U.norm(p)
  p = (p:gsub('\\', '/'))
  if #p > 3 then p = (p:gsub('/+$', '')) end
  if p:match('^%a:$') then p = p .. '/' end
  return p
end

-- key used to compare paths and to index notes / pins: normalized and lowercase
function U.key(p)
  return U.norm(p):lower()
end

function U.parent_path(p)
  local up = p:match('^(.*)/[^/]+$')
  if not up then return nil end
  if up:match('^%a:$') then up = up .. '/' end
  return up
end

function U.read_file(p)
  local f = io.open(p, 'r')
  if not f then return nil end
  local s = f:read('*a')
  f:close()
  return s
end

-- One scandir pass: returns the folder names and the other entry names, or nil if unreadable.
function U.scan(path)
  local h = uv.fs_scandir(path)
  if not h then return nil end
  local dirs, files = {}, {}
  while true do
    local name, t = uv.fs_scandir_next(h)
    if not name then break end
    if t == 'directory' then dirs[#dirs + 1] = name else files[#files + 1] = name end
  end
  return dirs, files
end

-- resolved highlight attributes (links followed)
function U.hl(name)
  return api.nvim_get_hl(0, { name = name, link = false })
end

-- screen size available to floating windows
function U.screen()
  return vim.o.columns, vim.o.lines - vim.o.cmdheight
end

-- run `fn` for a list of keymap lhs
function U.map(buf, keys, fn, modes)
  for _, k in ipairs(keys) do
    vim.keymap.set(modes, k, fn, { buffer = buf, nowait = true, silent = true })
  end
end

return U
