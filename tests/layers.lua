-- The layers, bottom first (CODING_STANDARDS.md): each requires only
-- itself and the layers below it. The rebuild goes bottom-up, and `built`
-- is how far it has got: the layers up to it are held to the rules
-- (independence_spec) and to every check lua-language-server has (make
-- lint). Above it is today's code, held to neither.

return {
  built = 2,
  -- The surfaces' layer: they open each other through thread.go.
  surfaces = 8,
  layers = {
    { 'thread.base', 'thread.config' },
    { 'thread.ui' },
    { 'thread.store' },
    { 'thread.model' },
    { 'thread.prose' },
    { 'thread.draw' },
    { 'thread.actions' },
    { 'thread.go', 'thread.screen', 'thread.code', 'thread.walk', 'thread.focus', 'thread.page', 'thread.map', 'thread.compose' },
    { 'thread' },
  },
}
