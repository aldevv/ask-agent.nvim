# ask-agent.nvim

Ask a CLI agent (default `claude -p`) about the current visual selection
or search match, get the answer back in a floating window. Native sibling
to the ask flow in [md-preview](https://github.com/aldevv/md-preview), but
inside Neovim instead of a browser.

Requires Neovim 0.10+ (uses `vim.system`) and whatever CLI you point
`command` at on `$PATH`.

## Install (lazy.nvim)

```lua
{
  "aldevv/ask-agent.nvim",
  keys = { { "<leader>a", mode = { "n", "x" }, desc = "Ask agent" } },
  cmd = { "Ask" },
  opts = {},
}
```

## Usage

- Visual-select some text, press `<leader>a`, type your question.
- Or in normal mode with an active search (`/foo<CR>`), press `<leader>a`
  to ask about the match.
- Falls back to the system clipboard when there's no selection or search.
- `:Ask` works too; with a range it uses the range, otherwise the same
  auto rules apply.

In the answer window:

- `q` / `<Esc>` / `<C-c>` close.
- `a` opens a follow-up prompt that keeps the conversation context.
- `<leader><Tab>` / `<leader><S-Tab>` cycle forward/back through the
  session's Q+A history.

All four are configurable (see `keys` below).

## Config

Defaults:

```lua
require("ask-agent").setup({
  command = "claude -p",           -- shell-split on whitespace; argv[0] is the binary
  system_prompt =
    "Answer their question about it concisely. Output plain markdown. "
    .. "If you need more context than the selection provides, read the file directly.",
  timeout_ms = 60000,              -- hard kill after this
  max_output_bytes = 256 * 1024,   -- cap stdout/stderr
  keymap = "<leader>a",            -- set to false to skip
  command_name = "Ask",            -- set to false / "" to skip
  float = {
    width = 0.5,                   -- fraction of editor width (hard cap)
    height = 0.8,                  -- fraction of editor height (hard cap)
    pref_width = 80,               -- preferred width when content is narrow
    border = "rounded",
    anchor = "selection",          -- "selection" | "center" | "cursor"
  },
  keys = {                         -- buffer-local maps inside the answer window
    close     = { "q", "<Esc>", "<C-c>" },
    follow_up = "a",
    prev      = "<leader><S-Tab>", -- previous Q+A in this session
    next      = "<leader><Tab>",   -- next Q+A in this session
  },
  notify = nil,                    -- override vim.notify for tests
})
```

Any CLI that reads a prompt on stdin works. Swap the default by setting
`command`:

```lua
require("ask-agent").setup({
  command = "codex exec",          -- or "gemini -p", "llm -m gpt-4o", etc.
})
```

Selection text, system prompt, and question go over **stdin**, never
argv, so shell escaping stays out of the picture.
