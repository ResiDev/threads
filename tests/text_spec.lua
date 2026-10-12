-- Text as it is drawn: widths, cutting and padding, counts and times.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local text = require 'thread.base.text'

R.test('fit: cuts by display width and never loops', function()
  R.eq(text.fit('hello', 0), '', 'no room')
  R.eq(text.fit('hello', -3), '', 'less than none')
  R.eq(text.fit('hello', 5), 'hello', 'fits')
  R.eq(text.fit('hello', 4), 'hel…', 'cut')
  R.eq(text.fit('hello', 1), '…', 'room for the ellipsis only')
  R.eq(text.fit('日本語です', 5), '日本…', 'wide characters take two columns')
  R.eq(text.width(text.fit('日本語です', 4)), 3, 'never half a character')
end)

R.test('width of chunks, pad and plural', function()
  R.eq(text.width { { 'ab' }, { '日' } }, 4, 'chunks add up')
  R.eq(text.pad('é', 3), 'é  ', 'pads by columns, not bytes')
  R.eq(text.plural(1, 'line'), '1 line')
  R.eq(text.plural(2, 'line'), '2 lines')
  R.eq(text.plural(2, 'match', 'matches'), '2 matches')
end)

R.test('ago and since', function()
  local restore = H.freeze_time '2026-10-11T12:00:00'
  R.eq(text.ago '2026-10-11T11:59:30', 'just now')
  R.eq(text.ago '2026-10-11T11:48:00', '12m ago')
  R.eq(text.ago '2026-10-11T09:00:00', '3h ago')
  R.eq(text.ago '2026-10-08T12:00:00', '3d ago')
  R.eq(text.ago 'not a time', nil)
  R.eq(text.since(7200), '2h ago')
  restore()
end)
