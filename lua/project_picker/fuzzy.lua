-- Fuzzy matching and ranking of folder nodes.
local F = {}

local BOUNDARY = '[/_%-%. ]'

-- Fuzzy match of `tok` in `s` (lowercase; `orig` keeps the case for camelCase boundaries).
-- A plain substring scores highest; otherwise the letters must appear in order, with bonuses
-- for consecutive letters and word starts (after / _ - . space, or a camelCase hump).
-- Returns nil when there is no match. `subseq` = false allows substring matches only.
function F.score(tok, s, orig, subseq)
  if tok == '' then return 0 end
  local pos = s:find(tok, 1, true)
  if pos then
    local start = pos == 1 or s:sub(pos - 1, pos - 1):match(BOUNDARY) ~= nil
    return 100 + (start and 20 or 0) + #tok * 2
  end
  if subseq == false then return nil end
  local score, si, prev, first = 0, 1, 0, nil
  for i = 1, #tok do
    local p = s:find(tok:sub(i, i), si, true)
    if not p then return nil end
    first = first or p
    score = score + 1
    if p == prev + 1 then score = score + 4 end
    if p == 1 or s:sub(p - 1, p - 1):match(BOUNDARY) then
      score = score + 6
    elseif orig:sub(p, p):match('%u') and orig:sub(p - 1, p - 1):match('%l') then
      score = score + 6
    end
    prev, si = p, p + 1
  end
  -- letters spread far apart are a weaker match than tight ones
  -- (and shorter names win over long ones with the same letters)
  return score - (prev - first + 1 - #tok) - #s * 0.3
end

-- lowercase words of a query
function F.tokens(q)
  local out = {}
  for t in q:lower():gmatch('%S+') do out[#out + 1] = t end
  return out
end

-- Rank `nodes` (fields: name, lname, path, key) against the query words. Every word must match
-- the name (worth double), the whole path (letters in order, words of 3+ characters only) or
-- the folder note. opts: accept(n) -> bool, notes (key -> text), limit.
function F.search(nodes, tokens, opts)
  local accept, notes = opts.accept, opts.notes
  local hits, nhits = {}, 0
  for _, n in ipairs(nodes) do
    if accept(n) then
      local note = notes[n.key]
      local note_l = note and note:lower()
      local total = 0
      for _, t in ipairs(tokens) do
        local sn = F.score(t, n.lname, n.name)
        local sp = F.score(t, n.key, n.path, #t >= 3)
        local sno = note and F.score(t, note_l, note, false)
        local s = math.max(sn and sn * 2 or -1, sp or -1, sno or -1)
        if s < 0 then total = nil break end
        total = total + s
      end
      if total then
        n.score = total
        nhits = nhits + 1
        hits[nhits] = n
      end
    end
  end
  local by_path = #tokens == 0 -- no query (projects view): plain alphabetical order
  table.sort(hits, function(a, b)
    if by_path then return a.path < b.path end
    if a.score ~= b.score then return a.score > b.score end
    if #a.path ~= #b.path then return #a.path < #b.path end
    return a.path < b.path
  end)
  local out = {}
  for i = 1, math.min(nhits, opts.limit or 300) do out[i] = hits[i] end
  return out
end

return F
