#!/bin/bash
# MacSynergy — Build, Package, and Create DMG
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MacSynergy"
VERSION="1.0.0"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BINARY_DST="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$SCRIPT_DIR/$DMG_NAME"

echo "🛑 Stopping any running $APP_NAME instances..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "🔨 Building $APP_NAME in release mode..."
cd "$SCRIPT_DIR"
swift build -c release

echo "📦 Packaging .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp ".build/arm64-apple-macosx/release/$APP_NAME" "$BINARY_DST"
chmod +x "$BINARY_DST"

echo "🔏 Signing..."
codesign --sign "MacSynergy Dev" --force --deep "$APP_BUNDLE" 2>/dev/null || \
codesign --sign - --force --deep --preserve-metadata=identifier,entitlements "$APP_BUNDLE" 2>/dev/null || true

echo "💿 Creating DMG..."
TEMP_DIR=$(mktemp -d)
MOUNT_DIR="$TEMP_DIR/mount"
mkdir -p "$MOUNT_DIR"

# Copy app into mount point
cp -r "$APP_BUNDLE" "$MOUNT_DIR/"
# Create Applications symlink for drag-install UX
ln -sf /Applications "$MOUNT_DIR/Applications"

# Remove old DMG if exists
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$MOUNT_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$TEMP_DIR"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ DMG created: $DMG_NAME"
echo "📂 Location: $DMG_PATH"
SIZE=$(du -sh "$DMG_PATH" | cut -f1)
echo "📏 Size: $SIZE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
