-- Project detection and the info panel: manifest markers, readable project name, git details.
local U = require('project_picker.util')
local uv = vim.uv or vim.loop

local P = {}

-- a folder is a project if it has .git or one of these files
local MARKER_FILES = {
  ['package.json'] = 'node', ['cargo.toml'] = 'rust', ['go.mod'] = 'go', ['pom.xml'] = 'java',
  ['build.gradle'] = 'java', ['build.gradle.kts'] = 'java', ['pyproject.toml'] = 'python',
  ['requirements.txt'] = 'python', ['composer.json'] = 'php', ['cmakelists.txt'] = 'cmake',
  ['gemfile'] = 'ruby',
}
local MARKER_EXT = { sln = '.NET', slnx = '.NET', csproj = '.NET', fsproj = '.NET', vbproj = '.NET' }
local DOTNET_EXT = { 'sln', 'slnx', 'csproj', 'fsproj', 'vbproj' } -- priority for the project name

local function marker_of(name)
  local l = name:lower()
  return MARKER_FILES[l] or MARKER_EXT[l:match('%.(%w+)$') or '']
end

-- distinct project kinds among the given file names ({ 'node', '.NET', ... })
function P.kinds(files)
  local kinds, seen = {}, {}
  for _, name in ipairs(files) do
    local k = marker_of(name)
    if k and not seen[k] then
      seen[k] = true
      kinds[#kinds + 1] = k
    end
  end
  return kinds
end

-- Readable project name from the manifest in the folder (package.json, *.sln, Cargo.toml, ...).
-- Cached by path; nil when the folder has no recognizable manifest.
local label_cache = {}
function P.label(path)
  if label_cache[path] ~= nil then return label_cache[path] or nil end
  local files = {} -- lowercase name -> real name
  for _, name in ipairs(select(2, U.scan(path)) or {}) do files[name:lower()] = name end
  local function text(file)
    return files[file] and U.read_file(path .. '/' .. files[file])
  end
  local function field(file, pat)
    local s = text(file)
    return s and s:match(pat)
  end
  local label = field('package.json', '"name"%s*:%s*"([^"]+)"')
    or field('composer.json', '"name"%s*:%s*"([^"]+)"')
    or field('cargo.toml', '%[package%].-name%s*=%s*"([^"]+)"')
    or field('pyproject.toml', '%[project%].-name%s*=%s*"([^"]+)"')
    or field('pyproject.toml', '%[tool%.poetry%].-name%s*=%s*"([^"]+)"')
  if not label then
    local go = field('go.mod', 'module%s+(%S+)')
    label = go and go:match('([^/]+)$')
  end
  if not label then
    local pom = text('pom.xml')
    label = pom and pom:gsub('<parent>.-</parent>', ''):match('<artifactId>([^<]+)</artifactId>')
  end
  if not label then
    for _, ext in ipairs(DOTNET_EXT) do
      for lower, orig in pairs(files) do
        if lower:match('%.' .. ext .. '$') then label = orig:gsub('%.%w+$', '') break end
      end
      if label then break end
    end
  end
  label_cache[path] = label or false
  return label
end

-- nearest folder (the path itself or a parent) that contains .git
function P.git_root(path)
  local cur = path
  while cur do
    if uv.fs_stat(U.join(cur, '.git')) then return cur end
    cur = U.parent_path(cur)
  end
end

-- lines for the git part of the info panel
local function git_lines(path, add)
  local root = P.git_root(path)
  if root == path then
    add('Git repository: YES', 'DiagnosticOk')
    local g = U.join(path, '.git')
    local st = uv.fs_stat(g)
    if st and st.type == 'directory' then
      local head = U.read_file(U.join(g, 'HEAD')) or ''
      local branch = head:match('ref:%s*refs/heads/(%S+)')
      add('  branch: ' .. (branch or ('detached ' .. head:sub(1, 8))))
      local cfg = U.read_file(U.join(g, 'config')) or ''
      add('  remote: ' .. (cfg:match('url%s*=%s*([^\r\n]+)') or '(none)'))
    else
      add('  (.git is a file: worktree or submodule)', 'Comment')
    end
  elseif root then
    add('Git repository: inside a repo, not its root', 'DiagnosticWarn')
    add('  root: ' .. root, 'Comment')
  else
    add('Git repository: no', 'DiagnosticWarn')
  end
end

-- info panel content: list of { text, highlight group }
function P.info_lines(path, note)
  local L = {}
  local function add(t, h) L[#L + 1] = { t or '', h } end
  add(path, 'Title')
  if note then add('Note: ' .. note, 'String') end
  add('')
  local dirs, files = U.scan(path)
  if not dirs then
    add('Cannot read this folder', 'DiagnosticError')
    return L
  end
  add(('Folders: %d    Files: %d'):format(#dirs, #files))
  add('')
  git_lines(path, add)
  local kinds = P.kinds(files)
  if #kinds > 0 then add('Project type: ' .. table.concat(kinds, ', '), 'Special') end
  local label = P.label(path)
  if label then add('Project name: ' .. label, 'Special') end
  add('')
  add('Contents:', 'Special')
  -- folders first, then files, each sorted case-insensitively (first 5000 entries only)
  local function sorted(names, suffix)
    local out, lower = {}, {}
    for i = 1, math.min(#names, 5000) do
      out[i] = names[i]
      lower[names[i]] = names[i]:lower()
    end
    table.sort(out, function(a, b) return lower[a] < lower[b] end)
    for i, name in ipairs(out) do out[i] = name .. suffix end
    return out
  end
  local names = sorted(dirs, '/')
  vim.list_extend(names, sorted(files, ''))
  for i = 1, math.min(#names, 40) do
    add('  ' .. names[i], names[i]:sub(-1) == '/' and 'Directory' or nil)
  end
  if #names > 40 then add(('  ... %d more'):format(#names - 40), 'Comment') end
  return L
end

return P
