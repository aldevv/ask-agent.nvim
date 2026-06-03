local M = {}

local config = require("ask-agent.config")
local notify = require("ask-agent.notify")
local selection = require("ask-agent.selection")
local SOURCES = selection.SOURCES

local PROMPT = {
  file_header = "The user has selected the following text from the file at:\n%s\n(lines %d-%d)\n",
  sel_open = "--- Selection start ---",
  sel_close = "--- Selection end ---",
  history_header = "Earlier in this conversation:",
  q_prefix = "Q: ",
  a_prefix = "A: ",
  question_prefix = "Question: ",
  followup_prefix = "Follow-up Q: ",
  entry_fmt = "> %s\n\n%s",
}

local _initialized = false
local _state = { handle = nil, job = nil, thinking = nil, session = nil }

local function clear_thinking()
  if _state.thinking then
    _state.thinking:stop()
    _state.thinking = nil
  end
end

local function clear_job()
  if _state.job then
    _state.job:cancel()
    _state.job = nil
  end
end

local function clear_window()
  if _state.handle then
    require("ask-agent.ui").close(_state.handle)
    _state.handle = nil
  end
end

local function reset_all()
  clear_thinking()
  clear_job()
  clear_window()
  _state.session = nil
end

local function split_argv(command)
  local argv = {}
  for word in command:gmatch("%S+") do
    table.insert(argv, word)
  end
  return argv
end

local function render_entry(question, answer)
  if not question or question == "" then return answer end
  return string.format(PROMPT.entry_fmt, question, answer or "")
end

local function navigate(delta)
  local s = _state.session
  if not s or not _state.handle then return end
  local n = #s.history
  if n <= 1 then return end
  local cur = s.cursor or n
  local new = ((cur - 1 + delta) % n) + 1
  s.cursor = new
  local entry = s.history[new]
  require("ask-agent.ui").set_content(_state.handle, render_entry(entry.question, entry.answer))
end

local function build_prompt(sel, question, history, system_prompt)
  local parts = {}
  if sel.file and sel.file ~= "" then
    table.insert(parts, string.format(PROMPT.file_header, sel.file, sel.start_line, sel.end_line))
  end
  if system_prompt and system_prompt ~= "" then table.insert(parts, system_prompt .. "\n") end
  table.insert(parts, PROMPT.sel_open .. "\n" .. sel.text .. "\n" .. PROMPT.sel_close .. "\n")

  if history and #history > 0 then
    table.insert(parts, PROMPT.history_header)
    for _, turn in ipairs(history) do
      table.insert(parts, PROMPT.q_prefix .. turn.question)
      table.insert(parts, PROMPT.a_prefix .. turn.answer)
    end
    table.insert(parts, PROMPT.followup_prefix .. question)
  else
    table.insert(parts, PROMPT.question_prefix .. question)
  end

  return table.concat(parts, "\n")
end

local run

local function make_callbacks(sel)
  return {
    on_close = function()
      _state.handle = nil
      _state.session = nil
    end,
    on_follow_up = function()
      clear_window()
      require("ask-agent.prompt").ask(function(q)
        if not q then return end
        run(sel, q)
      end)
    end,
    on_prev = function() navigate(-1) end,
    on_next = function() navigate(1) end,
  }
end

function run(sel, question)
  local opts = config.opts
  local argv = split_argv(opts.command)
  if #argv == 0 then
    notify.err("config.command is empty")
    return
  end

  local ui = require("ask-agent.ui")
  clear_window()
  clear_thinking()
  clear_job()

  _state.thinking = ui.start_thinking(sel)

  if not _state.session then _state.session = { sel = sel, history = {} } end

  local payload = build_prompt(sel, question, _state.session.history, opts.system_prompt)
  local callbacks = make_callbacks(sel)

  _state.job = require("ask-agent.job").start(argv, payload, {
    timeout_ms = opts.timeout_ms,
    max_output_bytes = opts.max_output_bytes,
  }, function(result)
    clear_thinking()
    _state.job = nil

    if result.timed_out then
      _state.handle = ui.show_error(string.format("timed out after %dms", opts.timeout_ms), opts.float, sel, callbacks)
      return
    end
    if result.code ~= 0 then
      local err = result.stderr ~= "" and result.stderr or result.stdout
      if err == "" then err = string.format("exit code %d", result.code) end
      _state.handle = ui.show_error(err, opts.float, sel, callbacks)
      return
    end

    table.insert(_state.session.history, { question = question, answer = result.stdout })
    _state.session.cursor = #_state.session.history
    _state.handle = ui.show(render_entry(question, result.stdout), opts.float, sel, callbacks)
  end)
end

function M.setup(user_opts)
  config.merge(user_opts)
  if _initialized then return end
  _initialized = true

  local opts = config.opts

  if opts.command_name and opts.command_name ~= "" then
    vim.api.nvim_create_user_command(
      opts.command_name,
      function(ev) M.ask(ev.range > 0 and SOURCES.VISUAL or SOURCES.AUTO) end,
      { range = true, desc = "Ask the configured agent about the selection / search match" }
    )
  end

  if opts.keymap then
    vim.keymap.set("x", opts.keymap, function()
      vim.cmd("noautocmd normal! \27")
      M.ask(SOURCES.VISUAL)
    end, { desc = "ask-agent: ask about selection", silent = true })
    vim.keymap.set(
      "n",
      opts.keymap,
      function() M.ask(SOURCES.AUTO) end,
      { desc = "ask-agent: ask about search match", silent = true }
    )
  end
end

function M.ask(source)
  local sel = selection.get(source or SOURCES.AUTO)
  if not sel or sel.text == "" then
    notify.warn("no selection or active search")
    return
  end

  require("ask-agent.prompt").ask(function(question)
    if not question then return end
    reset_all()
    run(sel, question)
  end)
end

function M.close() reset_all() end

return M
