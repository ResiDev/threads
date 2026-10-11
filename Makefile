NVIM ?= nvim

.PHONY: test screens smoke check

# Unit tests: every tests/*_spec.lua. SPEC=name runs only those matching.
test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# End to end: a thread, a tour walked, a review, the skill's checker.
smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

# Every screen as text, against tests/screens/. UPDATE=1 writes them anew.
screens:
	@UPDATE=$(UPDATE) $(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/screens.lua

check: test screens smoke
