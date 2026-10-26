-- Window geometry: search line over the folder list on the left, info panel on the right,
-- optional animation window further left; everything centered on the screen.
local U = require('project_picker.util')

local L = {}

-- Returns the configs { input, list, prev, anim? } and the animation actually used (the
-- animation is dropped when the screen is too small for it).
function L.compute(anim)
  local W, H = U.screen()
  local width = math.max(60, math.floor(W * 0.8))
  local height = math.max(14, math.floor(H * 0.75))
  width, height = math.min(width, W), math.min(height, H)
  local ao = anim and (anim.cols + 2) or 0 -- outer width of the animation window
  if anim then
    width = math.min(width, W - 2 - ao - 1)
    if width < 70 or H < anim.rows + 2 then anim, ao = nil, 0 end
  end
  local gap = anim and 1 or 0
  local row = math.floor((H - height) / 2)
  local col = math.floor((W - width - ao - gap) / 2) + ao + gap
  local lw = math.floor(width * 0.5) - 2
  local pw = width - lw - 4
  local out = {
    input = { relative = 'editor', row = row, col = col, width = lw, height = 1 },
    list = { relative = 'editor', row = row + 3, col = col, width = lw, height = height - 5 },
    prev = { relative = 'editor', row = row, col = col + lw + 2, width = pw, height = height - 2 },
  }
  if anim then
    out.anim = {
      relative = 'editor', row = math.floor((H - anim.rows - 2) / 2), col = col - ao - gap,
      width = anim.cols, height = anim.rows,
    }
  end
  return out, anim
end

-- common options of the picker's floating windows
function L.wopts(cfg, title, extra)
  return vim.tbl_extend('force', cfg, {
    style = 'minimal', border = 'rounded', title = title, title_pos = 'center',
  }, extra or {})
end

return L
