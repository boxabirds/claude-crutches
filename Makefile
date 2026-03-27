VERSION ?= 1.0.0

.PHONY: vendor build build-unsigned release clean test

# Vendor Python dependencies (openpyxl)
vendor:
	bash scripts/vendor-deps.sh

# Full build: sign + notarize + DMG
build: vendor
	VERSION=$(VERSION) bash scripts/build-app.sh

# Dev build: sign but skip notarization (faster)
build-dev: vendor
	VERSION=$(VERSION) bash scripts/build-app.sh --skip-notarize

# Local build: no signing at all
build-unsigned: vendor
	VERSION=$(VERSION) bash scripts/build-app.sh --unsigned

# Cut a release: build + sign + notarize + GitHub release
release:
	bash scripts/release.sh

# Run unit tests
test: vendor
	bash tests/test_excel_to_csv.sh

# Run end-to-end tests with real Excel files
test-e2e: vendor
	bash tests/test_e2e.sh

# Run all tests
test-all: test test-e2e

clean:
	rm -rf .build vendor
