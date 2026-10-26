-- Persistent data in nvim's data dir: recent / pinned / root folders, notes, chosen animation.
local Config = require('project_picker.config')
local U = require('project_picker.util')

local S = {}

function S.load()
  local s = U.read_file(Config.opts.store_file)
  local ok, data = pcall(vim.json.decode, s or '{}')
  if not ok or type(data) ~= 'table' then data = {} end
  for _, field in ipairs({ 'recent', 'pinned', 'roots', 'notes' }) do
    if type(data[field]) ~= 'table' then data[field] = {} end
  end
  return data -- notes: lowercase path -> short text
end

function S.save(data)
  pcall(vim.fn.writefile, { vim.json.encode(data) }, Config.opts.store_file)
end

function S.ago(t)
  local d = os.time() - t
  if d < 60 then return 'just now' end
  if d < 3600 then return ('%d min ago'):format(math.floor(d / 60)) end
  if d < 86400 then return ('%d h ago'):format(math.floor(d / 3600)) end
  return ('%d d ago'):format(math.floor(d / 86400))
end

-- pinned / root lookup sets, rebuilt only after a change (kept outside the saved table)
local caches = setmetatable({}, { __mode = 'k' })
local function sets(s)
  local c = caches[s]
  if not c then
    c = { pinned = {}, roots = {} }
    for _, name in ipairs({ 'pinned', 'roots' }) do
      for _, p in ipairs(s[name]) do c[name][U.key(p)] = true end
    end
    caches[s] = c
  end
  return c
end

function S.is_pinned(s, key) return sets(s).pinned[key] end
function S.is_root(s, key) return sets(s).roots[key] end

-- add `path` to s[list] or remove it when present; returns true when it was added
function S.toggle(s, list, path)
  local key = U.key(path)
  caches[s] = nil
  for i, p in ipairs(s[list]) do
    if U.key(p) == key then
      table.remove(s[list], i)
      return false
    end
  end
  s[list][#s[list] + 1] = U.norm(path)
  return true
end

-- remember `path` as the most recently opened folder
function S.record(s, path)
  S.forget(s, path)
  table.insert(s.recent, 1, { path = U.norm(path), time = os.time() })
  while #s.recent > Config.opts.recent_max do table.remove(s.recent) end
  S.save(s)
end

-- drop `path` from the recent list; true when it was there (saved)
function S.forget(s, path)
  local key = U.key(path)
  for i, e in ipairs(s.recent) do
    if U.key(e.path) == key then
      table.remove(s.recent, i)
      return true
    end
  end
  return false
end

return S
