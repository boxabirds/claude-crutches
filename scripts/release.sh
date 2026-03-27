#!/usr/bin/env bash
# Release Claude Crutches: build, sign, notarize, and create a GitHub release.
#
# Usage:
#   ./scripts/release.sh           # Auto-increment patch version
#   ./scripts/release.sh 1.2.0     # Use specific version
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Determine version ---
CURRENT_VERSION=$(grep '^VERSION' "$PROJECT_DIR/Makefile" | head -1 | awk -F'=' '{print $2}' | tr -d ' ' || echo "1.0.0")

if [ -n "${1:-}" ]; then
    NEW_VERSION="$1"
else
    # Auto-increment patch
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    PATCH=$((PATCH + 1))
    NEW_VERSION="$MAJOR.$MINOR.$PATCH"
fi

echo "==> Releasing Claude Crutches v${NEW_VERSION} (was v${CURRENT_VERSION})"

# --- Preflight checks ---
echo "==> Preflight checks"

if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install: brew install gh"
    exit 1
fi

# Check signing identity
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "ERROR: No Developer ID Application certificate in keychain."
    exit 1
fi

# Check clean working directory
if [ -n "$(git -C "$PROJECT_DIR" status --porcelain)" ]; then
    echo "ERROR: Working directory is not clean. Commit or stash changes first."
    exit 1
fi

# --- Update version in Makefile ---
echo "==> Updating version to $NEW_VERSION"
sed -i '' "s/^VERSION ?= .*/VERSION ?= $NEW_VERSION/" "$PROJECT_DIR/Makefile"

# Commit version bump
git -C "$PROJECT_DIR" add Makefile
git -C "$PROJECT_DIR" commit -m "Bump version to $NEW_VERSION"

# --- Vendor dependencies ---
echo "==> Vendoring dependencies"
bash "$SCRIPT_DIR/vendor-deps.sh"

# --- Build, sign, notarize ---
echo "==> Building release"
VERSION="$NEW_VERSION" bash "$SCRIPT_DIR/build-app.sh"

DMG_PATH="$PROJECT_DIR/.build/Claude-Crutches-${NEW_VERSION}.dmg"

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    exit 1
fi

# --- Tag and release ---
echo "==> Creating git tag v${NEW_VERSION}"
git -C "$PROJECT_DIR" tag "v${NEW_VERSION}"
git -C "$PROJECT_DIR" push origin main
git -C "$PROJECT_DIR" push origin "v${NEW_VERSION}"

echo "==> Creating GitHub release"
gh release create "v${NEW_VERSION}" \
    --repo "$(git -C "$PROJECT_DIR" remote get-url origin | sed 's/\.git$//')" \
    --title "Claude Crutches v${NEW_VERSION}" \
    --notes "$(cat <<EOF
## Claude Crutches v${NEW_VERSION}

### Excel → CSV Converter
Drop Excel files (.xlsx, .xls) or folders onto the app icon to convert each sheet to a separate CSV file.

### Installation
1. Download \`Claude-Crutches-${NEW_VERSION}.dmg\`
2. Open the DMG
3. Drag **Claude Crutches** to your Applications folder (or anywhere you like)
4. Optionally drag it to your Dock for quick access

### Requirements
- macOS 13.0 (Ventura) or later
- Python 3 (included with Xcode Command Line Tools)
EOF
)" \
    "$DMG_PATH"

echo ""
echo "==> RELEASE COMPLETE"
echo "    Version: v${NEW_VERSION}"
echo "    DMG:     $DMG_PATH"
echo "    GitHub:  $(gh release view "v${NEW_VERSION}" --json url -q .url 2>/dev/null || echo 'check GitHub')"
