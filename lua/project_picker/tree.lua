-- Folder tree model: drives as roots, lazily loaded children, hidden rules, background crawl.
local Config = require('project_picker.config')
local U = require('project_picker.util')
local Project = require('project_picker.project')
local uv = vim.uv or vim.loop

local T = {}
T.__index = T


-- hidden by default: dot folders, big/generated folders at any depth, Windows system folders
-- in a drive root
local IGNORE = {
  ['node_modules'] = true, ['__pycache__'] = true, ['venv'] = true, ['bower_components'] = true,
}
local SYSTEM_ROOT = {
  ['$recycle.bin'] = true, ['system volume information'] = true, ['$windows.~bt'] = true,
  ['$windows.~ws'] = true, ['$winreagent'] = true, ['recovery'] = true, ['config.msi'] = true,
  ['documents and settings'] = true, ['msocache'] = true, ['perflogs'] = true,
  ['programdata'] = true, ['windows'] = true, ['program files'] = true, ['program files (x86)'] = true,
}
local function hidden_name(lname, depth)
  return lname:sub(1, 1) == '.' or IGNORE[lname] == true or (depth == 1 and SYSTEM_ROOT[lname] == true)
end

function T.new()
  local self = setmetatable({ roots = {}, all = {}, show_hidden = false, queue = {}, qi = 1 }, T)
  for i = 65, 90 do
    local letter = string.char(i)
    if uv.fs_stat(letter .. ':/') then
      self.roots[#self.roots + 1] = self:mk(letter .. ':/', letter .. ':', nil)
    end
  end
  for _, r in ipairs(self.roots) do self.queue[#self.queue + 1] = r end
  return self
end

-- Node fields: path, key (lowercase path), name, lname, parent, depth, children, hidden,
-- loaded, kinds (project kinds, known once loaded), git (nil = not known yet), label (drives).
function T:mk(path, name, parent)
  local lname = name:lower()
  local depth = parent and parent.depth + 1 or 0
  local n = {
    path = path, key = path:lower(), name = name, lname = lname, parent = parent,
    depth = depth, children = {},
    hidden = (parent and parent.hidden) or hidden_name(lname, depth),
  }
  self.all[#self.all + 1] = n
  return n
end

-- read the sub-folders of a node (once); also learns its project kinds and whether it has .git
function T:load(n)
  if n.loaded then return end
  n.loaded = true
  local dirs, files = U.scan(n.path)
  if not dirs then return end
  n.kinds = Project.kinds(files)
  -- .git is a folder normally, a file for worktrees and submodules
  n.git = vim.tbl_contains(dirs, '.git') or vim.tbl_contains(files, '.git')
  local lower = {}
  for _, name in ipairs(dirs) do lower[name] = name:lower() end
  table.sort(dirs, function(a, b) return lower[a] < lower[b] end)
  for _, name in ipairs(dirs) do
    n.children[#n.children + 1] = self:mk(U.join(n.path, name), name, n)
  end
end

-- has .git; looked up only when the node has not been loaded yet
function T:has_git(n)
  if n.git == nil then n.git = uv.fs_stat(U.join(n.path, '.git')) ~= nil end
  return n.git
end

function T:is_project(n)
  return self:has_git(n) or (n.kinds ~= nil and #n.kinds > 0)
end

function T:vis(n)
  return self.show_hidden or not n.hidden
end

function T:visible_count(n)
  local c = 0
  for _, ch in ipairs(n.children) do
    if self:vis(ch) then c = c + 1 end
  end
  return c
end

-- node for a path (loading the folders on the way), or nil
function T:find(path)
  path = U.norm(path)
  local drive = path:match('^(%a:)')
  if not drive then return nil end
  drive = drive:lower()
  local cur
  for _, r in ipairs(self.roots) do
    if r.lname == drive then cur = r end
  end
  if not cur then return nil end
  for seg in path:sub(4):gmatch('[^/]+') do
    self:load(cur)
    seg = seg:lower()
    local nxt
    for _, c in ipairs(cur.children) do
      if c.lname == seg then nxt = c break end
    end
    if not nxt then return nil end
    cur = nxt
  end
  return cur
end

-- visible nodes in tree order (expanded folders show their children)
function T:flatten(nodes, out)
  out = out or {}
  for _, n in ipairs(nodes or self.roots) do
    if self:vis(n) then
      out[#out + 1] = n
      if n.expanded and n.loaded then self:flatten(n.children, out) end
    end
  end
  return out
end

-- Background crawl, a slice at a time, so searches find folders that were never expanded.
-- Returns true when something was loaded; use crawl_pending() to know if there is more.
function T:crawl_step(budget)
  local changed = false
  while budget > 0 and self.qi <= #self.queue and #self.all < Config.opts.crawl_max do
    local n = self.queue[self.qi]
    self.qi = self.qi + 1
    if n.depth < Config.opts.crawl_depth and not n.hidden then
      self:load(n)
      changed = true
      -- do not crawl inside a detected project (its sub-folders are not project roots)
      if not self:is_project(n) then
        for _, c in ipairs(n.children) do self.queue[#self.queue + 1] = c end
      end
    end
    budget = budget - 1
  end
  return changed
end

function T:crawl_pending()
  return self.qi <= #self.queue and #self.all < Config.opts.crawl_max
end

-- volume labels like "This PC" shows: "C: (Local Disk)"; async, `on_ready` runs when set
function T:fetch_drive_labels(on_ready)
  local drive_types = { [2] = 'Removable Disk', [3] = 'Local Disk', [4] = 'Network Drive', [5] = 'CD Drive' }
  pcall(vim.system, {
    'powershell.exe', '-NoProfile', '-NonInteractive', '-Command',
    "Get-CimInstance Win32_LogicalDisk | ForEach-Object { $_.DeviceID + '|' + $_.DriveType + '|' + $_.VolumeName }",
  }, { text = true }, function(res)
    vim.schedule(function()
      for line in (res.stdout or ''):gmatch('[^\r\n]+') do
        local id, dt, name = line:match('^(%a:)|(%d*)|(.*)$')
        for _, r in ipairs(self.roots) do
          if id and r.name:upper() == id:upper() then
            if name == '' then name = drive_types[tonumber(dt)] or 'Drive' end
            r.label = r.name .. ' (' .. name .. ')'
          end
        end
      end
      if on_ready then on_ready() end
    end)
  end)
end

return T
