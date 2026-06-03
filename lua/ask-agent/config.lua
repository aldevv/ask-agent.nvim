local M = {}

M.defaults = {
  command = "claude -p",
  system_prompt = "Answer their question about it concisely. Output plain markdown. "
    .. "If you need more context than the selection provides, read the file directly.",
  timeout_ms = 60000,
  max_output_bytes = 256 * 1024,
  keymap = "<leader>a",
  command_name = "Ask",
  float = {
    width = 0.5,
    height = 0.8,
    pref_width = 80,
    border = "rounded",
    anchor = "selection",
  },
  keys = {
    close = { "q", "<Esc>", "<C-c>" },
    follow_up = "a",
    prev = "<leader><S-Tab>",
    next = "<leader><Tab>",
  },
  notify = nil,
}

M.opts = vim.deepcopy(M.defaults)

function M.merge(user)
  if not user then return end
  for k, v in pairs(user) do
    if type(v) == "table" and type(M.opts[k]) == "table" then
      M.opts[k] = vim.tbl_deep_extend("force", M.opts[k], v)
    else
      M.opts[k] = v
    end
  end
end

return M
