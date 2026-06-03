local M = {}

local function clamp(s, max)
  if #s <= max then return s end
  return s:sub(1, max)
end

function M.start(argv, stdin, opts, on_done)
  opts = opts or {}
  local timeout_ms = opts.timeout_ms or 60000
  local max_bytes = opts.max_output_bytes or (256 * 1024)

  local handle = { cancelled = false, sys = nil }

  handle.sys = vim.system(argv, {
    stdin = stdin,
    text = true,
    timeout = timeout_ms,
  }, function(obj)
    if handle.cancelled then return end
    vim.schedule(
      function()
        on_done({
          code = obj.code or 0,
          signal = obj.signal or 0,
          stdout = clamp(obj.stdout or "", max_bytes),
          stderr = clamp(obj.stderr or "", max_bytes),
          timed_out = (obj.code or 0) == 124,
        })
      end
    )
  end)

  function handle:cancel()
    if self.cancelled then return end
    self.cancelled = true
    pcall(function() self.sys:kill(15) end)
  end

  return handle
end

return M
