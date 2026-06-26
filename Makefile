.PHONY: test

NVIM ?= nvim
MINIMAL_INIT := scripts/minimal_init.lua

test:
	$(NVIM) --headless \
		-u $(MINIMAL_INIT) \
		-c "lua require('plenary.test_harness').test_directory('spec', { minimal_init = '$(MINIMAL_INIT)' })" \
		-c "qa"
