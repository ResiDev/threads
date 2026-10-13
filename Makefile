NVIM ?= nvim
MASON ?= $(HOME)/.local/share/nvim/mason/bin
STYLUA ?= $(shell command -v stylua || echo $(MASON)/stylua)
LUALS ?= $(shell command -v lua-language-server || echo $(MASON)/lua-language-server)

.PHONY: test screens surfaces smoke lint check try bench

# Unit tests: every tests/*_spec.lua. SPEC=name runs only those matching.
test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# How long the code takes to draw a big file under many threads; not in
# check. LINES=2000 for a smaller one.
bench:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/bench.lua

# End to end: a thread, a tour walked, a review.
smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

# Every screen as text, against tests/screens/. UPDATE=1 writes them anew.
screens:
	@UPDATE=$(UPDATE) $(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/screens.lua

# The rebuild's surfaces as text, against tests/surfaces/. UPDATE=1 writes
# them anew.
surfaces:
	@UPDATE=$(UPDATE) $(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/surfaces.lua

# Formatting; then what lua-language-server finds: in the whole repository
# with .luarc.json, and with every check on (.luarc.strict.json) in the
# layers the rebuild has built (tests/layers.lua). Files over 600 lines are
# named, not failed.
LOG := $(or $(TMPDIR),/tmp)/thread-luals
# .luarc.json reads Neovim's own types from $VIMRUNTIME/lua.
export VIMRUNTIME ?= $(shell $(NVIM) --clean --headless -c 'lua io.stdout:write(vim.env.VIMRUNTIME)' -c qa)
# $(call luals,<dir>,<config>,<name>): its problems into $(LOG)/<name>.json.
# It exits 1 when it finds any, so whether it ran is read from what it says.
luals = out=$$($(LUALS) --check $(1) --configpath $(CURDIR)/$(2) --checklevel=Hint --logpath $(LOG) \
	  --check_format=json --check_out_path=$(LOG)/$(3).json 2>&1); \
	  echo "$$out" | grep -q 'Diagnosis complete' || { echo "$$out" | tail -20; exit 1; }

lint:
	@$(STYLUA) --check lua tests skills plugin
	@rm -f $(LOG)/loose.json $(LOG)/strict.json
	@$(call luals,.,.luarc.json,loose)
	@$(call luals,lua,.luarc.strict.json,strict)
	@$(NVIM) --clean -l tests/lint.lua $(LOG)/loose.json $(LOG)/strict.json
	@find lua -name '*.lua' -exec wc -l {} + | awk '$$2 != "total" && $$1 > 600 { print "lint: " $$2 " is " $$1 " lines" }'
	@echo 'lint: ok'

check: test screens surfaces smoke lint

# The rebuild's surfaces, to try: Neovim with your own config, on a copy
# of this repository at the code the reviews in tests/reviews/ are about,
# with those reviews in its .threads/.
TRY := $(or $(TMPDIR),/tmp)/thread-try
try:
	@rm -rf $(TRY) && git clone -q --shared . $(TRY) && git -C $(TRY) checkout -q 9cde8c4
	@mkdir -p $(TRY)/.threads && cp tests/reviews/*.json $(TRY)/.threads/ && echo '/.threads/' >> $(TRY)/.git/info/exclude
	@cd $(TRY) && THREAD_REBUILD=1 $(NVIM)
