#!/usr/bin/env bash
# End-to-end tests using real-world Excel files.
# Exercises the full converter against downloaded sample data.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONVERTER="$PROJECT_DIR/src/excel_to_csv.py"
VENDOR_DIR="$PROJECT_DIR/vendor"
DATA_DIR="$SCRIPT_DIR/data"
WORK_DIR=$(mktemp -d)
PASS=0
FAIL=0

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

export PYTHONPATH="$VENDOR_DIR"

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

assert_min_lines() {
    local desc="$1" path="$2" min="$3"
    local count
    count=$(wc -l < "$path" | tr -d ' ')
    if [ "$count" -ge "$min" ]; then
        echo "  PASS: $desc ($count lines)"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc (got $count lines, need >= $min)"
        FAIL=$((FAIL + 1))
    fi
}

assert_csv_header_contains() {
    local desc="$1" path="$2" expected_col="$3"
    local header
    header=$(head -1 "$path" | tr -d '\r')
    if echo "$header" | grep -qi "$expected_col"; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc — header: $header"
        FAIL=$((FAIL + 1))
    fi
}

# ============================================================
# Test 1: Financial Sample (1 sheet, ~700 rows)
# ============================================================
echo "=== Test 1: Financial Sample (single sheet) ==="
SRC="$DATA_DIR/financial-sample.xlsx"
cp "$SRC" "$WORK_DIR/"
XLSX="$WORK_DIR/financial-sample.xlsx"

python3 "$CONVERTER" "$XLSX"
OUT="$XLSX-csv"

SHEET_COUNT=$(ls "$OUT"/*.csv 2>/dev/null | wc -l | tr -d ' ')
assert_eq "exactly 1 CSV produced" "1" "$SHEET_COUNT"
assert_file_exists "Sheet1.csv exists" "$OUT/Sheet1.csv"
assert_min_lines "Sheet1 has substantial data (>=700 rows)" "$OUT/Sheet1.csv" 700
assert_csv_header_contains "header contains Segment" "$OUT/Sheet1.csv" "Segment"
assert_csv_header_contains "header contains Country" "$OUT/Sheet1.csv" "Country"

# ============================================================
# Test 2: Northwind (13 sheets)
# ============================================================
echo "=== Test 2: Northwind (13 sheets) ==="
SRC="$DATA_DIR/northwind.xlsx"
cp "$SRC" "$WORK_DIR/"
XLSX="$WORK_DIR/northwind.xlsx"

python3 "$CONVERTER" "$XLSX"
OUT="$XLSX-csv"

SHEET_COUNT=$(ls "$OUT"/*.csv 2>/dev/null | wc -l | tr -d ' ')
assert_eq "13 CSVs produced" "13" "$SHEET_COUNT"

# Spot-check key sheets
assert_file_exists "categories.csv" "$OUT/categories.csv"
assert_file_exists "customers.csv" "$OUT/customers.csv"
assert_file_exists "orders.csv" "$OUT/orders.csv"
assert_file_exists "products.csv" "$OUT/products.csv"
assert_file_exists "employees.csv" "$OUT/employees.csv"
assert_file_exists "suppliers.csv" "$OUT/suppliers.csv"
assert_file_exists "usstates.csv" "$OUT/usstates.csv"

assert_min_lines "orders has substantial data (>=800 rows)" "$OUT/orders.csv" 800
assert_min_lines "customers has data (>=50 rows)" "$OUT/customers.csv" 50
assert_min_lines "products has data (>=50 rows)" "$OUT/products.csv" 50
assert_csv_header_contains "orders header has OrderID" "$OUT/orders.csv" "OrderID"

# ============================================================
# Test 3: AdventureWorks Sales (7 sheets, large data)
# ============================================================
echo "=== Test 3: AdventureWorks Sales (7 sheets, large) ==="
SRC="$DATA_DIR/adventureworks-sales.xlsx"
cp "$SRC" "$WORK_DIR/"
XLSX="$WORK_DIR/adventureworks-sales.xlsx"

python3 "$CONVERTER" "$XLSX"
OUT="$XLSX-csv"

SHEET_COUNT=$(ls "$OUT"/*.csv 2>/dev/null | wc -l | tr -d ' ')
assert_eq "7 CSVs produced" "7" "$SHEET_COUNT"

assert_file_exists "Sales_data.csv" "$OUT/Sales_data.csv"
assert_file_exists "Customer_data.csv" "$OUT/Customer_data.csv"
assert_file_exists "Product_data.csv" "$OUT/Product_data.csv"
assert_file_exists "Date_data.csv" "$OUT/Date_data.csv"
assert_file_exists "Sales Order_data.csv" "$OUT/Sales Order_data.csv"
assert_file_exists "Reseller_data.csv" "$OUT/Reseller_data.csv"
assert_file_exists "Sales Territory_data.csv" "$OUT/Sales Territory_data.csv"

assert_min_lines "Sales_data has substantial rows (>=10000)" "$OUT/Sales_data.csv" 10000
assert_min_lines "Customer_data has rows (>=1000)" "$OUT/Customer_data.csv" 1000
assert_min_lines "Product_data has rows (>=100)" "$OUT/Product_data.csv" 100

# ============================================================
# Test 4: Idempotency — re-running skips existing
# ============================================================
echo "=== Test 4: Idempotency (all three refuse second run) ==="
for name in financial-sample northwind adventureworks-sales; do
    if python3 "$CONVERTER" "$WORK_DIR/$name.xlsx" 2>/dev/null; then
        echo "  FAIL: $name should have been skipped"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $name correctly refused (output exists)"
        PASS=$((PASS + 1))
    fi
done

# ============================================================
# Test 5: Folder drop simulation (all three in one folder)
# ============================================================
echo "=== Test 5: Folder with multiple Excel files ==="
FOLDER="$WORK_DIR/mixed-folder"
mkdir -p "$FOLDER"
cp "$DATA_DIR/financial-sample.xlsx" "$FOLDER/"
cp "$DATA_DIR/northwind.xlsx" "$FOLDER/"

# Convert each file in folder (simulates what the AppleScript does)
CONVERTED=0
for xlsx in "$FOLDER"/*.xlsx; do
    python3 "$CONVERTER" "$xlsx"
    CONVERTED=$((CONVERTED + 1))
done
assert_eq "converted 2 files from folder" "2" "$CONVERTED"
assert_file_exists "folder: financial CSV dir created" "$FOLDER/financial-sample.xlsx-csv/Sheet1.csv"
assert_file_exists "folder: northwind CSV dir created" "$FOLDER/northwind.xlsx-csv/orders.csv"

# ============================================================
# Test 6: CSV round-trip sanity — no data corruption
# ============================================================
echo "=== Test 6: Data integrity spot-checks ==="

# Check that numeric data survived (financial sample has numbers)
SECOND_LINE=$(sed -n '2p' "$WORK_DIR/financial-sample.xlsx-csv/Sheet1.csv" | tr -d '\r')
FIELD_COUNT=$(echo "$SECOND_LINE" | awk -F',' '{print NF}')
# Financial sample has 16 columns
assert_eq "financial sample row has correct column count" "16" "$FIELD_COUNT"

# Check northwind categories has expected number of categories (8)
CATEGORY_ROWS=$(tail -n +2 "$WORK_DIR/northwind.xlsx-csv/categories.csv" | wc -l | tr -d ' ')
assert_eq "northwind categories has 8 rows" "8" "$CATEGORY_ROWS"

# ===== Summary =====
echo ""
echo "============================================"
echo "E2E Results: $PASS passed, $FAIL failed"
echo "============================================"
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
