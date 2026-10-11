NVIM ?= nvim

.PHONY: test smoke check

# Unit tests: every tests/*_spec.lua. SPEC=name runs only those matching.
test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# End to end: a thread, a tour walked, a review, the skill's checker.
smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

check: test smoke
