# Claude Crutches

A macOS droplet app that converts Excel and PDF files into Claude-friendly formats. Drop files onto the app icon and get back CSVs and structured markdown that you can upload directly to Claude.

## Supported Formats

| Input | Output |
|-------|--------|
| `.xlsx`, `.xls` | Folder of CSVs (one per sheet) |
| `.pdf` | Folder with `content.md` (extracted text) and `images/` (rendered pages) |

You can drop individual files or entire folders — the app will find all convertible files recursively.

## Requirements

- macOS 13.0+
- Xcode Command Line Tools (for building the Swift PDF converter)
- Python 3 (ships with macOS; needed at runtime for Excel conversion)

## Build

```bash
# Full build: sign + notarize + DMG
make build

# Dev build: sign but skip notarization
make build-dev

# Local build: no signing
make build-unsigned
```

The output is a DMG at `.build/Claude-Crutches-<version>.dmg`.

## Test

```bash
make test          # Excel unit tests
make test-pdf      # PDF integration tests
make test-e2e      # End-to-end with real files
make test-all      # All of the above
```

## Release

```bash
make release       # Build + sign + notarize + GitHub release
```

## How It Works

The app is a native macOS AppleScript droplet that dispatches to two bundled converters:

- **`pdf_to_files`** — Swift binary using macOS PDFKit to extract text and render page images
- **`excel_to_csv.py`** — Thin Python script using vendored openpyxl to split sheets into CSVs

PDF conversion is entirely native (Swift + PDFKit). Excel conversion uses Python only because there's no native macOS API for reading `.xlsx` files.

## License

Apache 2.0
