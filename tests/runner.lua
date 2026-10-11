--- The test runner: `test(name, fn)`, `eq` and `ok`. `tests/run.lua` runs
--- every tests/*_spec.lua with it in one Neovim; `make test`.

local R = { count = 0, failures = 0 }

---@param name string
---@param fn fun()
function R.test(name, fn)
  R.count = R.count + 1
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    R.failures = R.failures + 1
    io.stderr:write('FAIL ' .. name .. ':\n' .. tostring(err) .. '\n')
  end
end

function R.eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s: expected %s, got %s', what or 'value', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function R.ok(value, what)
  if not value then
    error(what or 'expected a true value', 2)
  end
  return value
end

return R
