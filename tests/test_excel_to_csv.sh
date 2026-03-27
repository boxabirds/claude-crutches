#!/usr/bin/env bash
# Tests for the Excel-to-CSV converter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONVERTER="$PROJECT_DIR/src/excel_to_csv.py"
VENDOR_DIR="$PROJECT_DIR/vendor"
TEST_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

export PYTHONPATH="$VENDOR_DIR"

# --- Helper: create a test Excel file ---
create_test_xlsx() {
    local path="$1"
    local sheets="${2:-Sheet1}"
    python3 -c "
import sys
sys.path.insert(0, '$VENDOR_DIR')
from openpyxl import Workbook
wb = Workbook()
sheets = '${sheets}'.split(',')
for i, name in enumerate(sheets):
    if i == 0:
        ws = wb.active
        ws.title = name
    else:
        ws = wb.create_sheet(title=name)
    ws.append(['header_a', 'header_b'])
    ws.append(['val_1', 'val_2'])
    ws.append(['val_3', 'val_4'])
wb.save('$path')
"
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_exists() {
    local desc="$1" path="$2"
    if [ -f "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — file not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    local desc="$1" path="$2"
    if [ -d "$path" ]; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — dir not found: $path"
        FAIL=$((FAIL + 1))
    fi
}

# ===== Test 1: Single sheet =====
echo "Test 1: Single-sheet Excel file"
XLSX="$TEST_DIR/simple.xlsx"
create_test_xlsx "$XLSX" "Data"
python3 "$CONVERTER" "$XLSX"
assert_dir_exists "output directory created" "$XLSX-csv"
assert_file_exists "CSV for sheet exists" "$XLSX-csv/Data.csv"
LINES=$(wc -l < "$XLSX-csv/Data.csv" | tr -d ' ')
assert_eq "CSV has 3 rows" "3" "$LINES"

# ===== Test 2: Multiple sheets =====
echo "Test 2: Multi-sheet Excel file"
XLSX="$TEST_DIR/multi.xlsx"
create_test_xlsx "$XLSX" "Revenue,Expenses,Summary"
python3 "$CONVERTER" "$XLSX"
assert_dir_exists "output directory created" "$XLSX-csv"
assert_file_exists "Revenue.csv exists" "$XLSX-csv/Revenue.csv"
assert_file_exists "Expenses.csv exists" "$XLSX-csv/Expenses.csv"
assert_file_exists "Summary.csv exists" "$XLSX-csv/Summary.csv"

# ===== Test 3: Already exists (should fail) =====
echo "Test 3: Skip if output already exists"
XLSX="$TEST_DIR/already.xlsx"
create_test_xlsx "$XLSX" "Sheet1"
python3 "$CONVERTER" "$XLSX"
# Second run should fail
if python3 "$CONVERTER" "$XLSX" 2>/dev/null; then
    echo "  FAIL: should have exited non-zero for existing output"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: exits non-zero when output exists"
    PASS=$((PASS + 1))
fi

# ===== Test 4: Sheet name with spaces and special chars =====
echo "Test 4: Sheet name with spaces and allowed special characters"
XLSX="$TEST_DIR/special.xlsx"
python3 -c "
import sys
sys.path.insert(0, '$VENDOR_DIR')
from openpyxl import Workbook
wb = Workbook()
ws = wb.active
ws.title = 'Q1 & Q2 Results (draft)'
ws.append(['a', 'b'])
wb.save('$XLSX')
"
python3 "$CONVERTER" "$XLSX"
assert_file_exists "sheet name with spaces preserved" "$XLSX-csv/Q1 & Q2 Results (draft).csv"

# ===== Test 5: CSV content correctness =====
echo "Test 5: CSV content is correct"
XLSX="$TEST_DIR/content.xlsx"
create_test_xlsx "$XLSX" "Check"
python3 "$CONVERTER" "$XLSX"
FIRST_LINE=$(head -1 "$XLSX-csv/Check.csv" | tr -d '\r')
assert_eq "header row correct" "header_a,header_b" "$FIRST_LINE"

# ===== Summary =====
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
