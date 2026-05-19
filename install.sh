#!/bin/bash
# MacSynergy — Build, Package, and Launch
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="MacSynergy"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME.app"
BINARY_DST="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "🛑 Stopping any running MacSynergy instances..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.3

echo "🔨 Building $APP_NAME in release mode..."
cd "$SCRIPT_DIR"
swift build -c release

echo "📦 Packaging .app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp ".build/arm64-apple-macosx/release/$APP_NAME" "$BINARY_DST"
chmod +x "$BINARY_DST"

# Sign with the stable self-signed "MacSynergy Dev" certificate (created once in login keychain).
# Certificate-based designated requirement survives rebuilds → TCC keeps Accessibility grant.
# Falls back to ad-hoc if the cert is missing (first-time setup on a new machine).
codesign --sign "MacSynergy Dev" --force --deep "$APP_BUNDLE" 2>/dev/null || \
codesign --sign - --force --deep --preserve-metadata=identifier,entitlements "$APP_BUNDLE" 2>/dev/null || true

echo "✅ Build & package complete!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🚀 Launching MacSynergy..."
open "$APP_BUNDLE"
echo ""
echo "⌨️  Press [ Shift + Space ] to open the AI overlay"
echo "❌ Press [ Escape ] or click outside to close"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
