#!/usr/bin/env bash
# Build, sign, notarize, and package Claude Crutches as a signed DMG.
#
# Usage:
#   ./scripts/build-app.sh                    # Full build + sign + notarize + DMG
#   ./scripts/build-app.sh --skip-notarize    # Build + sign only (faster, dev builds)
#   ./scripts/build-app.sh --unsigned          # No signing at all (local dev)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# --- Configuration ---
APP_NAME="Claude Crutches"
BUNDLE_ID="com.claudecrutches.app"
VERSION="${VERSION:-1.0.0}"
DISPLAY_NAME="Claude Crutches"
NOTARY_PROFILE="${NOTARY_PROFILE:-notarytool-profile}"
MIN_MACOS="13.0"

# --- Paths ---
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/Claude-Crutches-${VERSION}.dmg"
SRC_DIR="$PROJECT_DIR/src"
RESOURCES_DIR="$PROJECT_DIR/resources"
VENDOR_DIR="$PROJECT_DIR/vendor"

# --- Parse flags ---
SKIP_NOTARIZE=false
UNSIGNED=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --unsigned) UNSIGNED=true; SKIP_NOTARIZE=true ;;
        *) echo "Unknown flag: $arg"; exit 1 ;;
    esac
done

# --- Preflight checks ---
echo "==> Preflight checks"

if [ ! -d "$VENDOR_DIR/openpyxl" ]; then
    echo "ERROR: Vendor directory not found. Run: make vendor"
    exit 1
fi

if ! command -v osacompile &>/dev/null; then
    echo "ERROR: osacompile not found. Xcode Command Line Tools required."
    exit 1
fi

# --- Find signing identity ---
SIGNING_IDENTITY=""
if [ "$UNSIGNED" = false ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}' || true)
    if [ -z "$SIGNING_IDENTITY" ]; then
        echo "WARNING: No Developer ID Application certificate found."
        echo "         Building unsigned. Install a Developer ID cert for distribution."
        UNSIGNED=true
        SKIP_NOTARIZE=true
    else
        echo "    Signing identity: $SIGNING_IDENTITY"
    fi
fi

# --- Clean build directory ---
echo "==> Cleaning build directory"
rm -rf "$APP_BUNDLE" "$DMG_PATH"
mkdir -p "$BUILD_DIR"

# --- Compile Swift PDF converter ---
echo "==> Compiling Swift PDF converter (universal binary)"
SWIFT_OUT="$BUILD_DIR/pdf-to-files"
swiftc -O \
    -target arm64-apple-macosx${MIN_MACOS} \
    -o "${SWIFT_OUT}-arm64" \
    "$SRC_DIR/pdf_to_files.swift" \
    -framework PDFKit -framework AppKit -framework CoreGraphics
swiftc -O \
    -target x86_64-apple-macosx${MIN_MACOS} \
    -o "${SWIFT_OUT}-x86_64" \
    "$SRC_DIR/pdf_to_files.swift" \
    -framework PDFKit -framework AppKit -framework CoreGraphics
lipo -create "${SWIFT_OUT}-arm64" "${SWIFT_OUT}-x86_64" -output "$SWIFT_OUT"
rm "${SWIFT_OUT}-arm64" "${SWIFT_OUT}-x86_64"
echo "    Built universal binary: $SWIFT_OUT"

# --- Compile AppleScript droplet ---
echo "==> Compiling AppleScript droplet"
osacompile -o "$APP_BUNDLE" "$SRC_DIR/droplet.applescript"

# --- Embed resources ---
echo "==> Embedding resources"
CONTENTS_DIR="$APP_BUNDLE/Contents"
APP_RESOURCES="$CONTENTS_DIR/Resources"

# Copy Python converter script + vendored packages (for Excel)
cp "$SRC_DIR/excel_to_csv.py" "$APP_RESOURCES/"
cp -R "$VENDOR_DIR" "$APP_RESOURCES/vendor"

# Copy Swift PDF converter binary
cp "$SWIFT_OUT" "$APP_RESOURCES/pdf-to-files"
chmod +x "$APP_RESOURCES/pdf-to-files"

# --- Customise Info.plist ---
echo "==> Configuring Info.plist"
PLIST="$CONTENTS_DIR/Info.plist"

# Set bundle identifier and version
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$PLIST"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$PLIST"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $VERSION" "$PLIST"

/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :CFBundleName string $DISPLAY_NAME" "$PLIST"

/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MIN_MACOS" "$PLIST" 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_MACOS" "$PLIST"

# Register accepted file types (Excel + folders)
# Remove any existing CFBundleDocumentTypes
/usr/libexec/PlistBuddy -c "Delete :CFBundleDocumentTypes" "$PLIST" 2>/dev/null || true

/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes array" "$PLIST"

# Excel files (.xlsx)
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string 'Excel Spreadsheet'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string org.openxmlformats.spreadsheetml.sheet" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string com.microsoft.excel.xls" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:2 string public.comma-separated-values-text" "$PLIST"

# PDF files
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeName string 'PDF Document'" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:CFBundleTypeRole string Viewer" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:1:LSItemContentTypes:0 string com.adobe.pdf" "$PLIST"

# Folders
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:2 dict" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:2:CFBundleTypeName string Folder" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:2:CFBundleTypeRole string Viewer" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:2:LSItemContentTypes array" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFBundleDocumentTypes:2:LSItemContentTypes:0 string public.folder" "$PLIST"

# --- Code Signing ---
if [ "$UNSIGNED" = false ]; then
    echo "==> Signing app bundle (inside-out)"

    # Sign all nested code first (vendored Python, scripts)
    find "$APP_BUNDLE" -type f -name "*.py" -o -name "*.sh" | while read -r f; do
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$f" 2>/dev/null || true
    done

    # Sign the compiled AppleScript
    if [ -f "$APP_RESOURCES/Scripts/main.scpt" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_RESOURCES/Scripts/main.scpt"
    fi

    # Sign the droplet executable (osacompile names it 'droplet' for on-open handlers)
    EXECUTABLE=$(find "$CONTENTS_DIR/MacOS" -type f | head -1)
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$EXECUTABLE"

    # Sign the whole bundle with entitlements
    codesign --force --options runtime --timestamp \
        --entitlements "$RESOURCES_DIR/entitlements.plist" \
        --sign "$SIGNING_IDENTITY" \
        "$APP_BUNDLE"

    echo "    Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
    echo "    Signature OK"
else
    echo "==> Skipping code signing (unsigned build)"
fi

# --- Notarization ---
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing app bundle"

    # Zip for notarization submission
    ZIP_PATH="$BUILD_DIR/Claude-Crutches-notarize.zip"
    ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout 1800

    echo "    Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE" || {
        echo "    Retry stapling in 5s (CDN propagation)..."
        sleep 5
        xcrun stapler staple "$APP_BUNDLE"
    }

    rm -f "$ZIP_PATH"
    echo "    Notarization complete"
else
    echo "==> Skipping notarization"
fi

# --- Create DMG ---
echo "==> Creating DMG"
hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

# --- Sign DMG ---
if [ "$UNSIGNED" = false ]; then
    echo "==> Signing DMG"
    codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH"
fi

# --- Notarize DMG ---
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "==> Notarizing DMG"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        --timeout 1800

    echo "    Stapling DMG..."
    xcrun stapler staple "$DMG_PATH" || {
        sleep 5
        xcrun stapler staple "$DMG_PATH"
    }
fi

# --- Verification ---
echo "==> Verification"

if [ "$UNSIGNED" = false ]; then
    echo "    App signature:"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" 2>&1 | head -5

    echo "    DMG signature:"
    codesign --verify --verbose "$DMG_PATH" 2>&1 | head -3

    if [ "$SKIP_NOTARIZE" = false ]; then
        echo "    Gatekeeper assessment (app):"
        spctl --assess --type execute --verbose "$APP_BUNDLE" 2>&1 || true

        echo "    Gatekeeper assessment (DMG):"
        spctl --assess --context context:primary-signature --verbose "$DMG_PATH" 2>&1 || true

        echo "    Staple validation:"
        xcrun stapler validate "$DMG_PATH" 2>&1 || true
    fi
fi

DMG_SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo ""
echo "==> BUILD COMPLETE"
echo "    App:     $APP_BUNDLE"
echo "    DMG:     $DMG_PATH ($DMG_SIZE)"
echo "    Version: $VERSION"
echo "    Signed:  $([ "$UNSIGNED" = false ] && echo 'YES' || echo 'NO')"
echo "    Notarized: $([ "$SKIP_NOTARIZE" = false ] && echo 'YES' || echo 'NO')"
