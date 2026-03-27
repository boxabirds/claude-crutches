VERSION ?= 1.1.0
MIN_MACOS ?= 13.0

.PHONY: vendor build-pdf-tool build build-unsigned release clean test test-pdf test-e2e test-all

# Vendor Python dependencies (openpyxl for Excel)
vendor:
	bash scripts/vendor-deps.sh

# Compile Swift PDF converter (universal binary)
build-pdf-tool:
	@mkdir -p .build
	swiftc -O -target arm64-apple-macosx$(MIN_MACOS) \
		-o .build/pdf-to-files-arm64 src/pdf_to_files.swift \
		-framework PDFKit -framework AppKit -framework CoreGraphics
	swiftc -O -target x86_64-apple-macosx$(MIN_MACOS) \
		-o .build/pdf-to-files-x86_64 src/pdf_to_files.swift \
		-framework PDFKit -framework AppKit -framework CoreGraphics
	lipo -create .build/pdf-to-files-arm64 .build/pdf-to-files-x86_64 -output .build/pdf-to-files
	@rm .build/pdf-to-files-arm64 .build/pdf-to-files-x86_64
	@echo "Built: .build/pdf-to-files"

# Full build: sign + notarize + DMG
build: vendor build-pdf-tool
	VERSION=$(VERSION) bash scripts/build-app.sh

# Dev build: sign but skip notarization (faster)
build-dev: vendor build-pdf-tool
	VERSION=$(VERSION) bash scripts/build-app.sh --skip-notarize

# Local build: no signing at all
build-unsigned: vendor build-pdf-tool
	VERSION=$(VERSION) bash scripts/build-app.sh --unsigned

# Cut a release: build + sign + notarize + GitHub release
release:
	bash scripts/release.sh

# Run Excel unit tests
test: vendor
	bash tests/test_excel_to_csv.sh

# Run PDF integration tests
test-pdf: build-pdf-tool
	bash tests/test_pdf_integration.sh

# Run end-to-end tests with real files
test-e2e: vendor build-pdf-tool
	bash tests/test_e2e.sh

# Run all tests
test-all: test test-pdf test-e2e

clean:
	rm -rf .build vendor
