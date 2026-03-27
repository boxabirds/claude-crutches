# Claude Crutches

A macOS app that converts Excel and PDF files into formats you can upload directly to Claude.

## How to Use

1. Download the DMG from the [latest release](../../releases/latest)
2. Open the DMG and drag **Claude Crutches** to your Applications folder
3. Drag it from Applications to your Dock for easy access
4. Drop files or folders onto the app icon

Converted output appears next to the original files:

- `report.xlsx` → `report.xlsx-csv/` (one CSV per sheet)
- `paper.pdf` → `paper.pdf-files/` (markdown text + rendered page images)

Supports `.xlsx`, `.xls`, and `.pdf`. You can drop folders too — the app finds all convertible files recursively.

## How to Build

Requires macOS 13.0+, Xcode Command Line Tools, and Python 3.

```bash
make build              # Full build: sign + notarize + DMG
make build-dev          # Sign but skip notarization (faster)
make build-unsigned     # No signing (local dev)
```

Output: `.build/Claude-Crutches-<version>.dmg`

```bash
make test-all           # Run all tests
make release            # Build + sign + notarize + GitHub release
```

### Architecture

Native macOS droplet app with two bundled converters:

- **`pdf_to_files`** — Swift binary using macOS PDFKit to extract text and render page images
- **`excel_to_csv.py`** — Python script using vendored openpyxl to split sheets into CSVs

## License

Apache 2.0
