local M = {}

local HL_BORDER = "FloatBorder"
local HL_KEY = "Special"
local HL_LABEL = "Comment"

local SPINNER_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local THINKING_TEXT = " thinking..."

local thinking_ns = vim.api.nvim_create_namespace("ask-agent-thinking")

local function as_list(k)
  if k == nil or k == false or k == "" then return {} end
  if type(k) == "string" then return { k } end
  return k
end

function M.start_thinking(sel)
  local handle = {
    buf = vim.api.nvim_get_current_buf(),
    line = nil,
    timer = nil,
  }
  if sel and sel.start_line and sel.start_line > 0 then
    handle.line = sel.start_line - 1
  else
    handle.line = vim.api.nvim_win_get_cursor(0)[1] - 1
  end

  local last = vim.api.nvim_buf_line_count(handle.buf) - 1
  if handle.line > last then handle.line = last end
  if handle.line < 0 then handle.line = 0 end

  local idx = 1
  local function render()
    if not vim.api.nvim_buf_is_valid(handle.buf) then return end
    pcall(vim.api.nvim_buf_clear_namespace, handle.buf, thinking_ns, 0, -1)
    pcall(vim.api.nvim_buf_set_extmark, handle.buf, thinking_ns, handle.line, 0, {
      virt_text = { { "  " .. SPINNER_FRAMES[idx] .. THINKING_TEXT, HL_LABEL } },
      virt_text_pos = "eol",
      hl_mode = "combine",
    })
    idx = idx % #SPINNER_FRAMES + 1
  end

  render()
  handle.timer = vim.uv.new_timer()
  handle.timer:start(100, 100, vim.schedule_wrap(render))

  function handle:stop()
    if self.timer then
      self.timer:stop()
      pcall(function() self.timer:close() end)
      self.timer = nil
    end
    if vim.api.nvim_buf_is_valid(self.buf) then
      pcall(vim.api.nvim_buf_clear_namespace, self.buf, thinking_ns, 0, -1)
    end
  end

  return handle
end

local function measure_height(lines, width)
  local h = 0
  for _, line in ipairs(lines) do
    local lw = vim.fn.strdisplaywidth(line)
    h = h + math.max(1, math.ceil(lw / math.max(1, width)))
  end
  return h
end

local function content_size(content, float_opts)
  local cols = vim.o.columns
  local rows = vim.o.lines

  local hard_max_w = math.max(40, math.floor(cols * (float_opts.width or 0.5)))
  local hard_max_h = math.max(10, math.floor(rows * (float_opts.height or 0.8)) - 2)
  local pref_w = math.min(hard_max_w, float_opts.pref_width or 80)
  local min_w = math.min(60, hard_max_w)
  local min_h = math.min(12, hard_max_h)

  local lines = vim.split(content, "\n", { plain = true })

  local longest = 0
  for _, line in ipairs(lines) do
    local lw = vim.fn.strdisplaywidth(line)
    if lw > longest then longest = lw end
  end

  local w = math.max(min_w, math.min(longest + 2, pref_w))
  local h = measure_height(lines, w) + 1
  h = math.max(min_h, math.min(h, hard_max_h))

  return w, h
end

local function position_for(w, h, float_opts, anchor, origin_win)
  local cols = vim.o.columns
  local rows = vim.o.lines
  local mode = float_opts.anchor or "selection"

  if mode == "cursor" then
    return {
      relative = "cursor",
      width = w,
      height = h,
      row = 1,
      col = 0,
      border = float_opts.border,
      style = "minimal",
    }
  end

  local function centered()
    return {
      relative = "editor",
      width = w,
      height = h,
      row = math.floor((rows - h) / 2),
      col = math.floor((cols - w) / 2),
      border = float_opts.border,
      style = "minimal",
    }
  end

  if mode ~= "selection" or not anchor or not anchor.start_line or anchor.start_line == 0 then return centered() end

  local ok, pos = pcall(vim.fn.screenpos, origin_win, anchor.start_line, 1)
  if not ok or not pos or pos.row == 0 then return centered() end

  local cmdline_rows = vim.o.cmdheight + 1
  local r = pos.row
  local row
  if rows - r - cmdline_rows >= h then
    row = r
  elseif r - 1 >= h then
    row = r - h - 1
  else
    return centered()
  end

  return {
    relative = "editor",
    width = w,
    height = h,
    row = row,
    col = math.floor((cols - w) / 2),
    border = float_opts.border,
    style = "minimal",
  }
end

local function first_key(keys)
  local list = as_list(keys)
  return list[1]
end

local function footer_chunks(callbacks, key_cfg)
  local chunks = {}
  local function add(key, label)
    table.insert(chunks, { " ", HL_BORDER })
    table.insert(chunks, { key, HL_KEY })
    table.insert(chunks, { label, HL_LABEL })
  end
  add(first_key(key_cfg.close) or "q", " close ")
  if callbacks and callbacks.on_follow_up and first_key(key_cfg.follow_up) then
    add(first_key(key_cfg.follow_up), " follow-up ")
  end
  if callbacks and callbacks.on_prev and callbacks.on_next and first_key(key_cfg.prev) and first_key(key_cfg.next) then
    add(first_key(key_cfg.prev) .. "/" .. first_key(key_cfg.next), " history ")
  end
  return chunks
end

local function open_float(content, float_opts, anchor, callbacks)
  local key_cfg = require("ask-agent.config").opts.keys or {}
  local origin_win = vim.api.nvim_get_current_win()
  local w, h = content_size(content, float_opts)
  local win_config = position_for(w, h, float_opts, anchor, origin_win)
  win_config.footer = footer_chunks(callbacks, key_cfg)
  win_config.footer_pos = "center"

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"

  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local win = vim.api.nvim_open_win(buf, true, win_config)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].cursorline = true
  vim.wo[win].conceallevel = 2
  vim.wo[win].concealcursor = "n"

  local handle = { buf = buf, win = win }

  local map_opts = { buffer = buf, nowait = true, silent = true }

  local function close()
    M.close(handle)
    if callbacks and callbacks.on_close then pcall(callbacks.on_close) end
  end
  for _, key in ipairs(as_list(key_cfg.close)) do
    vim.keymap.set("n", key, close, map_opts)
  end

  local function wrap(cb)
    return function()
      vim.schedule(function() pcall(cb) end)
    end
  end

  if callbacks and callbacks.on_follow_up then
    for _, key in ipairs(as_list(key_cfg.follow_up)) do
      vim.keymap.set("n", key, wrap(callbacks.on_follow_up), map_opts)
    end
  end
  if callbacks and callbacks.on_prev then
    for _, key in ipairs(as_list(key_cfg.prev)) do
      vim.keymap.set("n", key, wrap(callbacks.on_prev), map_opts)
    end
  end
  if callbacks and callbacks.on_next then
    for _, key in ipairs(as_list(key_cfg.next)) do
      vim.keymap.set("n", key, wrap(callbacks.on_next), map_opts)
    end
  end

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function() M.close(handle) end,
  })

  return handle
end

function M.set_content(handle, content)
  if not handle or not handle.buf or not vim.api.nvim_buf_is_valid(handle.buf) then return end
  local body = (content == nil or content == "") and "_(empty)_" or content
  local lines = vim.split(body, "\n", { plain = true })
  vim.bo[handle.buf].modifiable = true
  vim.api.nvim_buf_set_lines(handle.buf, 0, -1, false, lines)
  vim.bo[handle.buf].modifiable = false
  if handle.win and vim.api.nvim_win_is_valid(handle.win) then
    pcall(vim.api.nvim_win_set_cursor, handle.win, { 1, 0 })
  end
end

function M.show(content, float_opts, anchor, callbacks)
  local body = (content == nil or content == "") and "_(empty response)_" or content
  return open_float(body, float_opts, anchor, callbacks)
end

function M.show_error(msg, float_opts, anchor, callbacks)
  local body = "# Error\n\n```\n" .. (msg or "") .. "\n```"
  return open_float(body, float_opts, anchor, callbacks)
end

function M.close(handle)
  if not handle then return end
  if handle.win and vim.api.nvim_win_is_valid(handle.win) then pcall(vim.api.nvim_win_close, handle.win, true) end
  if handle.buf and vim.api.nvim_buf_is_valid(handle.buf) then
    pcall(vim.api.nvim_buf_delete, handle.buf, { force = true })
  end
end

return M
