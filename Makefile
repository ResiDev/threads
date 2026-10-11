NVIM ?= nvim
MASON ?= $(HOME)/.local/share/nvim/mason/bin
STYLUA ?= $(shell command -v stylua || echo $(MASON)/stylua)
LUALS ?= $(shell command -v lua-language-server || echo $(MASON)/lua-language-server)

.PHONY: test screens smoke lint check

# Unit tests: every tests/*_spec.lua. SPEC=name runs only those matching.
test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# End to end: a thread, a tour walked, a review, the skill's checker.
smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

# Every screen as text, against tests/screens/. UPDATE=1 writes them anew.
screens:
	@UPDATE=$(UPDATE) $(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/screens.lua

# Formatting, and the names lua-language-server finds unused or undefined.
# Files over 600 lines are named, not failed.
lint:
	@$(STYLUA) --check lua tests skills plugin
	@out=$$($(LUALS) --check lua --checklevel=Hint --configpath $(CURDIR)/.luarc.json --logpath $${TMPDIR:-/tmp}/thread-luals 2>&1); \
	  echo "$$out" | grep -q 'no problems found' || { echo "$$out" | tail -30; exit 1; }
	@find lua -name '*.lua' -exec wc -l {} + | awk '$$2 != "total" && $$1 > 600 { print "lint: " $$2 " is " $$1 " lines" }'
	@echo 'lint: ok'

check: test screens smoke lint
