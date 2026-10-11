NVIM ?= nvim

.PHONY: test smoke check

test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/spec.lua

smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

check: test smoke
