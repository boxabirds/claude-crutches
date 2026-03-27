#!/usr/bin/env bash
# Integration tests for PDF-to-files converter.
# Tests the Swift CLI tool against real PDF inputs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PDF_TOOL="$PROJECT_DIR/.build/pdf-to-files"
DATA_DIR="$SCRIPT_DIR/data"
WORK_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# --- Helpers ---
assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (expected=$expected, actual=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

assert_true() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

assert_false() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $desc (expected failure but succeeded)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    local desc="$1" path="$2"
    if [ -d "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_nonempty() {
    local desc="$1" path="$2"
    if [ -s "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file empty or missing: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_min_file_count() {
    local desc="$1" dir="$2" min="$3"
    local count
    count=$(find "$dir" -type f | wc -l | tr -d ' ')
    if [ "$count" -ge "$min" ]; then
        echo "  PASS: $desc ($count files)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (got $count files, need >= $min)"
        FAIL=$((FAIL + 1))
    fi
}

# --- Preflight ---
if [ ! -x "$PDF_TOOL" ]; then
    echo "ERROR: pdf-to-files not found at $PDF_TOOL"
    echo "       Run: make build-pdf-tool"
    exit 1
fi

# ============================================================
# Test 1: Multi-page PDF with tables and figures (arxiv paper)
# ============================================================
echo "=== Test 1: Complex PDF (arxiv paper, 24 pages) ==="
cp "$DATA_DIR/arxiv-tables.pdf" "$WORK_DIR/"
PDF="$WORK_DIR/arxiv-tables.pdf"
OUT="$PDF-files"

"$PDF_TOOL" "$PDF"
assert_dir_exists "output directory created" "$OUT"
assert_file_exists "content.md exists" "$OUT/content.md"
assert_file_nonempty "content.md is non-empty" "$OUT/content.md"
assert_dir_exists "images/ directory exists" "$OUT/images"
# 24 pages = at least 24 page render images
assert_min_file_count "at least 24 images for 24 pages" "$OUT/images" 24
# Content should reference images
assert_true "content.md references images" grep -q '!\[Page 1\]' "$OUT/content.md"
# Content should have extracted text
assert_true "content.md contains paper title" grep -q 'CHAIN-OF-TABLE' "$OUT/content.md"

# ============================================================
# Test 2: Simple text-only PDF
# ============================================================
echo "=== Test 2: Simple text-only PDF ==="
cp "$DATA_DIR/text-only.pdf" "$WORK_DIR/"
PDF="$WORK_DIR/text-only.pdf"
OUT="$PDF-files"

"$PDF_TOOL" "$PDF"
assert_dir_exists "output directory created" "$OUT"
assert_file_nonempty "content.md is non-empty" "$OUT/content.md"
assert_dir_exists "images/ exists (no crash even with minimal content)" "$OUT/images"
assert_true "content.md contains text" grep -q 'Dummy PDF' "$OUT/content.md"

# ============================================================
# Test 3: Idempotency — refuses to overwrite
# ============================================================
echo "=== Test 3: Idempotency ==="
# Output from test 2 still exists
assert_false "second run exits non-zero" "$PDF_TOOL" "$WORK_DIR/text-only.pdf"
# Original output should be unchanged
assert_file_nonempty "original content.md still intact" "$WORK_DIR/text-only.pdf-files/content.md"

# ============================================================
# Test 4: Corrupt PDF — clean failure
# ============================================================
echo "=== Test 4: Corrupt PDF ==="
cp "$DATA_DIR/corrupt.pdf" "$WORK_DIR/"
PDF="$WORK_DIR/corrupt.pdf"
assert_false "corrupt PDF exits non-zero" "$PDF_TOOL" "$PDF"
assert_true "no partial output left" test ! -d "$PDF-files"

# ============================================================
# Test 5: Missing file — clean error
# ============================================================
echo "=== Test 5: Missing file ==="
assert_false "nonexistent file exits non-zero" "$PDF_TOOL" "$WORK_DIR/does-not-exist.pdf"

# ============================================================
# Test 6: No arguments — usage message
# ============================================================
echo "=== Test 6: No arguments ==="
assert_false "no args exits non-zero" "$PDF_TOOL"

# ============================================================
# Test 7: Mixed folder simulation (Excel + PDF)
# ============================================================
echo "=== Test 7: Mixed folder (Excel + PDF) ==="
FOLDER="$WORK_DIR/mixed"
mkdir -p "$FOLDER"
cp "$DATA_DIR/financial-sample.xlsx" "$FOLDER/"
cp "$DATA_DIR/text-only.pdf" "$FOLDER/"

# PDF conversion
"$PDF_TOOL" "$FOLDER/text-only.pdf"
assert_dir_exists "PDF output created in mixed folder" "$FOLDER/text-only.pdf-files"

# Excel conversion (uses Python)
PYTHONPATH="$PROJECT_DIR/vendor" python3 "$PROJECT_DIR/src/excel_to_csv.py" "$FOLDER/financial-sample.xlsx"
assert_dir_exists "Excel output created in mixed folder" "$FOLDER/financial-sample.xlsx-csv"

# Both coexist
assert_file_exists "PDF content.md in mixed folder" "$FOLDER/text-only.pdf-files/content.md"
assert_file_exists "Excel CSV in mixed folder" "$FOLDER/financial-sample.xlsx-csv/Sheet1.csv"

# ===== Summary =====
echo ""
echo "============================================"
echo "PDF Integration Results: $PASS passed, $FAIL failed"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
