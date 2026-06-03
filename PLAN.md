# ask-agent.nvim plan

A standalone Neovim plugin that mirrors the `c` (ask Claude about selection)
flow from [md-preview](https://github.com/aldevv/md-preview), but native:
no browser, no server, just a buffer and a floating window.

## UX

1. User picks a selection source. Two work:
   - **Visual selection** (charwise, linewise, or blockwise). Used when
     the keymap fires from visual mode, or `:Ask` is given a range.
   - **Search match** (`/foo<CR>` or `?foo<CR>`). Used when the keymap
     fires from normal mode and `v:hlsearch` is on. The match under (or
     after) the cursor is extracted via the pattern in `@/` and sent as
     the selection. If neither is available the user gets a `no
     selection or active search` toast.
2. User triggers the ask (default keymap `<leader>a` in normal or visual
   mode, or `:Ask`).
3. `vim.ui.input` opens at the bottom: "Ask:".
4. User types a question, hits enter.
5. A floating window opens near the selection with a spinner ("thinking...").
6. Plugin spawns the configured command (default `claude -p`) with the
   composed prompt (selection + question) on stdin.
7. When the process exits, the spinner is replaced with the response,
   rendered into a scratch buffer with `filetype=markdown` so any
   markdown render plugin (render-markdown.nvim, markview, treesitter)
   picks it up.
8. `q` or `<Esc>` closes the window. `<C-c>` while in flight cancels
   the job.

Whole-buffer ask (no selection, no search) is a future iteration.

## Prompt shape

Same template md-preview uses, with one addition: the absolute path of
the source buffer is included so the agent can `Read` more of the file
when the selection alone isn't enough context.

```
The user has selected the following text from the file at:
<absolute path>
(lines <start>-<end>)

Answer their question about it concisely. Output plain markdown. If you
need more context than the selection provides, read the file directly.

--- Selection start ---
<selection>
--- Selection end ---

Question: <prompt>
```

Selection + question + filepath go over **stdin**, never argv. Keeps
shell escaping out of the picture and matches md-preview's `realRunAsk`.

When the buffer has no file on disk yet (`bufname` is empty), the
filepath block is omitted and only the selection lands in the prompt.
The line numbers come from the visual marks (`'<` / `'>`); blockwise
visual still reports its anchor rows.

## Config (defaults)

```lua
require("ask-agent").setup({
  command = "claude -p",           -- shell-split on whitespace, argv[0] is the binary
  timeout_ms = 60000,              -- hard kill after this; surfaces as an error
  max_output_bytes = 256 * 1024,   -- cap stdout/stderr so a runaway job can't OOM nvim
  keymap = "<leader>a",            -- visual-mode trigger; set to false to skip
  command_name = "Ask",            -- :Ask in visual mode does the same thing
  float = {
    width  = 0.5,                  -- fraction of editor width
    height = 0.5,                  -- fraction of editor height
    border = "rounded",
    anchor = "selection",          -- "selection" (near sel) | "center" | "cursor"
  },
  notify = vim.notify,             -- override for tests / muted setups
})
```

No `provider` abstraction yet. `command` is just an argv string; swap
in `gemini -p`, `llm -m claude-3-5-sonnet`, or a wrapper script if you
want a different backend. Add a real provider table only if a second
user shows up wanting per-call routing.

## Layout

```
ask-agent.nvim/
├── PLAN.md
├── README.md
├── lua/ask-agent/
│   ├── init.lua          public entry: setup(), ask(), close()
│   ├── config.lua        defaults + merge
│   ├── selection.lua     pull the visual selection as a string
│   ├── prompt.lua        vim.ui.input wrapper, returns question or nil
│   ├── job.lua           spawn argv with stdin, async, capped, cancellable
│   ├── ui.lua            floating window: open, set_content, spinner, close
│   └── notify.lua        thin vim.notify wrapper used everywhere
└── plugin/ask-agent.lua  one-line guard, defers wiring to setup()
```

Modules are picked so each file has one job and tests can stub the next
layer without dragging the whole plugin in. `job.lua` is the only piece
that touches `vim.system`/`uv.spawn`; everything else is pure Lua.

## Module sketches

**selection.lua** — read the last visual selection via `vim.fn.getpos("'<")` /
`"'>"`. Handle all three visual modes (v, V, <C-v>). Strip trailing newline
for charwise. Returns `string` or `nil`.

**prompt.lua** — wraps `vim.ui.input({ prompt = "Ask: " }, cb)`. Cancel
returns `nil`. Empty-after-trim returns `nil` with a `notify.warn`.

**job.lua** — `M.start(argv, stdin, opts, on_done)`. Uses `vim.system`
(Neovim 0.10+). `on_done` gets `{ code, stdout, stderr, timed_out }`.
Honours `timeout_ms` and `max_output_bytes`. Returns a handle with
`:cancel()`.

**ui.lua** — opens a floating window with a scratch buffer, sets
`filetype=markdown`, `wrap`, `linebreak`, `cursorline`, modifiable off.
Spinner is a single-line virtual text updated on a 100ms timer until
`set_content` lands. `q`/`<Esc>`/`<C-c>` close (close cancels job too).
Anchor math: read selection rect, pick a corner that fits, fall back to
center.

**init.lua** — `M.setup(opts)` merges into config, registers the command
and the visual-mode keymap. `M.ask()` is the high-level entrypoint:
selection → prompt → open spinner → build payload → spawn → render or
error toast.

## Out of scope for v1

- History (md-preview persists per-file history; nvim has buffers + undo,
  start without it).
- Whole-file ask without a selection.
- Streaming output. `claude -p` doesn't stream by default; revisit if
  the default flips or someone wires `--stream`.
- Multi-turn / follow-up. Each `:Ask` is one round trip.
- Provider abstraction (see Config note above).
- `:checkhealth ask-agent`. Add once the plugin has shape; the v1 surface
  is one external dep (`claude` on PATH) and one Neovim version gate
  (`vim.system` requires 0.10+).

## Open questions

- **Anchor math edge case.** Selection that spans the whole screen
  leaves no room to anchor "near" it; falling back to center is fine
  but should be a deliberate threshold, not silent.
- **`vim.system` vs `uv.spawn`.** `vim.system` is friendlier and ships
  in 0.10. If someone wants 0.9 support, we'd swap to `uv.spawn` with
  manual pipe wiring. Default to `vim.system` and require 0.10.

## Milestones

- **M0 (this commit).** Plan + scaffold. No working code; modules return
  stub errors so `require("ask-agent")` loads cleanly.
- **M1.** `:Ask` works end to end with a floating window and a spinner.
  No history, no whole-file, no checkhealth.
- **M2.** Cancellation, error formatting (stderr snippet on non-zero
  exit, timeout message), keymap polish.
- **M3.** Docs (`doc/ask-agent.txt`), README install snippet for lazy.nvim
  / packer, `:checkhealth ask-agent`, smoke test in `tests/`.
