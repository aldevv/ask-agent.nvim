local M = {}

local VISUAL_CHAR = "v"
local VISUAL_BLOCK = "\22"

M.SOURCES = {
  VISUAL = "visual",
  SEARCH = "search",
  CLIPBOARD = "clipboard",
  AUTO = "auto",
}

function M.get_visual()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local sl, sc = s[2], s[3]
  local el, ec = e[2], e[3]
  if sl == 0 or el == 0 then return nil end
  local mode = vim.fn.visualmode()
  local lines = vim.fn.getline(sl, el)
  if #lines == 0 then return nil end
  if mode == VISUAL_CHAR then
    if #lines == 1 then
      lines[1] = lines[1]:sub(sc, ec)
    else
      lines[1] = lines[1]:sub(sc)
      lines[#lines] = lines[#lines]:sub(1, ec)
    end
  elseif mode == VISUAL_BLOCK then
    local lo = math.min(sc, ec)
    local hi = math.max(sc, ec)
    for i, l in ipairs(lines) do
      lines[i] = l:sub(lo, hi)
    end
  end
  return {
    text = table.concat(lines, "\n"),
    start_line = sl,
    end_line = el,
    file = vim.api.nvim_buf_get_name(0),
    source = M.SOURCES.VISUAL,
  }
end

function M.get_search()
  if vim.v.hlsearch == 0 then return nil end
  local pat = vim.fn.getreg("/")
  if pat == "" then return nil end
  local pos = vim.fn.searchpos(pat, "ncw")
  if pos[1] == 0 then return nil end
  local line = vim.fn.getline(pos[1])
  local matched = vim.fn.matchstr(line:sub(pos[2]), pat)
  if matched == "" then return nil end
  return {
    text = matched,
    start_line = pos[1],
    end_line = pos[1],
    file = vim.api.nvim_buf_get_name(0),
    source = M.SOURCES.SEARCH,
  }
end

function M.get_clipboard()
  local text = vim.fn.getreg("*")
  if text == nil or text == "" then text = vim.fn.getreg("+") end
  if text == nil or text == "" then return nil end
  return {
    text = text,
    start_line = 0,
    end_line = 0,
    file = "",
    source = M.SOURCES.CLIPBOARD,
  }
end

function M.get(prefer)
  if prefer == M.SOURCES.VISUAL then return M.get_visual() end
  if prefer == M.SOURCES.SEARCH then return M.get_search() end
  if prefer == M.SOURCES.CLIPBOARD then return M.get_clipboard() end
  return M.get_search() or M.get_visual() or M.get_clipboard()
end

return M
