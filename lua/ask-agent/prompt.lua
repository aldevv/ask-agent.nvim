local M = {}

function M.ask(cb)
  vim.ui.input({ prompt = "Ask: " }, function(input)
    if not input then return cb(nil) end
    local trimmed = input:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return cb(nil) end
    cb(trimmed)
  end)
end

return M
