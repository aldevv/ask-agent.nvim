local M = {}

local function out()
  local cfg = require("ask-agent.config").opts
  return cfg.notify or vim.notify
end

function M.info(msg) out()(msg, vim.log.levels.INFO, { title = "ask-agent" }) end
function M.warn(msg) out()(msg, vim.log.levels.WARN, { title = "ask-agent" }) end
function M.err(msg)  out()(msg, vim.log.levels.ERROR, { title = "ask-agent" }) end

return M
