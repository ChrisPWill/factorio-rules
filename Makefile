LUA ?= lua
export LUA

.PHONY: validate package lint format test check

validate:
	python3 scripts/package.py --validate

package: validate
	python3 scripts/package.py

lint:
	stylua --check mod tests
	luacheck mod tests

format:
	stylua mod tests

test:
	$(LUA) tests/run.lua $(sort $(wildcard tests/unit/*_spec.lua))
	python3 -m unittest discover -s tests -p 'test_*.py' -v

check: validate lint test
