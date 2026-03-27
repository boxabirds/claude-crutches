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
- Python 3 (for Excel conversion; uses vendored `openpyxl`)

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

The app is an AppleScript droplet that dispatches to two converters:

- **`excel_to_csv.py`** — Python script using openpyxl to split each sheet into a CSV
- **`pdf_to_files`** — Native Swift binary using PDFKit to extract text and render page images

Both are bundled inside the `.app` along with vendored Python dependencies.

## License

Apache 2.0
