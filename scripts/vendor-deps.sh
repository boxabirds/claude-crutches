#!/usr/bin/env bash
# Vendor Python dependencies into vendor/ directory.
# These get bundled inside the .app for self-contained distribution.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENDOR_DIR="$PROJECT_DIR/vendor"

echo "==> Vendoring Python dependencies into $VENDOR_DIR"

# Clean previous vendor
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"

# Install openpyxl (and its dependency et_xmlfile) as pure Python packages
pip3 install --target "$VENDOR_DIR" --no-compile --no-deps openpyxl et_xmlfile

# Remove unnecessary metadata to keep bundle small
find "$VENDOR_DIR" -type d -name "*.dist-info" -exec rm -rf {} + 2>/dev/null || true
find "$VENDOR_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$VENDOR_DIR" -name "*.pyc" -delete 2>/dev/null || true

# Report size
VENDOR_SIZE=$(du -sh "$VENDOR_DIR" | cut -f1)
echo "==> Vendored dependencies: $VENDOR_SIZE"
echo "==> Contents:"
ls -1 "$VENDOR_DIR"
