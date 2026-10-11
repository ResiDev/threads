-- Every tests/*_spec.lua, in one Neovim. `SPEC=name make test` runs the
-- files whose name contains `name`.

local R = require 'tests.runner'
local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
for _, path in ipairs(vim.fn.glob(here .. '/*_spec.lua', false, true)) do
  if not vim.env.SPEC or vim.fs.basename(path):find(vim.env.SPEC, 1, true) then
    dofile(path)
  end
end
io.stdout:write(string.format('%d tests, %d failed\n', R.count, R.failures))
vim.cmd(R.failures > 0 and 'cquit 1' or 'qa!')
