local M = {}

local TITLE = "ask-agent"

local function out()
  local cfg = require("ask-agent.config").opts
  return cfg.notify or vim.notify
end

function M.info(msg) out()(msg, vim.log.levels.INFO, { title = TITLE }) end
function M.warn(msg) out()(msg, vim.log.levels.WARN, { title = TITLE }) end
function M.err(msg) out()(msg, vim.log.levels.ERROR, { title = TITLE }) end

return M
