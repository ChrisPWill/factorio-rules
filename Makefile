.PHONY: validate package

validate:
	python3 scripts/package.py --validate

package: validate
	python3 scripts/package.py
