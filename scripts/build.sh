#!/bin/bash
set -euo pipefail

APP_NAME=Voice2Text
BUNDLE_DIR="$APP_NAME.app"

# Find C++ include path dynamically
SDK_PATH=$(xcrun --show-sdk-path)
CXX_INCLUDE="$SDK_PATH/usr/include/c++/v1"

# Build
swift build -c release -Xcxx -I"$CXX_INCLUDE"

# Create .app bundle structure
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"

# Copy binary and Info.plist
cp .build/release/Voice2Text "$BUNDLE_DIR/Contents/MacOS/Voice2Text"
cp Resources/Info.plist "$BUNDLE_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

# Copy MLX metallib (required for GPU inference)
MLX_METALLIB="$(python3 -c 'import mlx; import os; print(os.path.join(os.path.dirname(mlx.__file__), "lib", "mlx.metallib"))' 2>/dev/null || true)"
if [ -f "$MLX_METALLIB" ]; then
    cp "$MLX_METALLIB" "$BUNDLE_DIR/Contents/MacOS/mlx.metallib"
elif [ -f "$HOME/repo/pyvoice2text/.venv/lib/python3.14/site-packages/mlx/lib/mlx.metallib" ]; then
    cp "$HOME/repo/pyvoice2text/.venv/lib/python3.14/site-packages/mlx/lib/mlx.metallib" "$BUNDLE_DIR/Contents/MacOS/mlx.metallib"
fi

# Ad-hoc sign
codesign -s - --force --deep "$BUNDLE_DIR"

# Install LaunchAgent plist with actual app path
ABSOLUTE_APP_PATH="$(cd "$(dirname "$BUNDLE_DIR")" && pwd)/$(basename "$BUNDLE_DIR")"
mkdir -p ~/Library/LaunchAgents
sed "s|__APP_PATH__|$ABSOLUTE_APP_PATH|g" Resources/com.local.voice2text.plist > ~/Library/LaunchAgents/com.local.voice2text.plist

echo "✅ Built successfully: $ABSOLUTE_APP_PATH"
echo "   LaunchAgent installed to ~/Library/LaunchAgents/com.local.voice2text.plist"
echo "   To load: launchctl load ~/Library/LaunchAgents/com.local.voice2text.plist"
echo ""
echo "   NOTE: For accessibility (global hotkey), either:"
echo "   1. Add Voice2Text.app in System Settings > Accessibility, OR"
echo "   2. Run directly: $BUNDLE_DIR/Contents/MacOS/Voice2Text &"
