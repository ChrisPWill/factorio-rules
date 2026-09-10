.PHONY: validate package lint format

validate:
	python3 scripts/package.py --validate

package: validate
	python3 scripts/package.py

lint:
	stylua --check mod
	luacheck mod

format:
	stylua mod
