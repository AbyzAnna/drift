#!/bin/bash
# Builds Drift.app from source and opens it.
#   bash build.sh            build into ./build and run
#   bash build.sh install    also copy to ~/Applications
#   bash build.sh share      build for Apple Silicon + Intel and make Drift-share.zip for friends
# Needs Xcode or the Command Line Tools:  xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "The Swift compiler isn't installed. Run:  xcode-select --install   then run this script again."
  exit 1
fi

ARCH="$(uname -m)"
APP="build/Drift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

FRAMEWORKS="-framework Cocoa -framework ServiceManagement -framework ApplicationServices"
if [[ "${1:-}" == "share" ]]; then
  echo "Compiling Drift for Apple Silicon and Intel..."
  swiftc -O -swift-version 5 -target arm64-apple-macos12.0 Sources/*.swift -o build/Drift-arm64 $FRAMEWORKS
  swiftc -O -swift-version 5 -target x86_64-apple-macos12.0 Sources/*.swift -o build/Drift-x86_64 $FRAMEWORKS
  lipo -create build/Drift-arm64 build/Drift-x86_64 -output "$APP/Contents/MacOS/Drift"
  rm -f build/Drift-arm64 build/Drift-x86_64
else
  echo "Compiling Drift for ${ARCH}..."
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos12.0" Sources/*.swift -o "$APP/Contents/MacOS/Drift" $FRAMEWORKS
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
# 3D-rendered characters (made with Tools/characters.py)
if [ -d Resources/Characters ]; then cp -R Resources/Characters "$APP/Contents/Resources/"; fi

# App icon (optional; skipped if the tools are missing)
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
if command -v sips >/dev/null && command -v iconutil >/dev/null; then
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "share" ]]; then
  rm -f Drift-share.zip
  ditto -c -k --keepParent "$APP" Drift-share.zip
  echo ""
  echo "Made Drift-share.zip. Send it to friends: they unzip it, drag Drift to Applications,"
  echo "then right-click Drift -> Open the first time (macOS asks because it isn't from the App Store)."
  exit 0
fi

if [[ "${1:-}" == "install" ]]; then
  mkdir -p "$HOME/Applications"
  pkill -x Drift 2>/dev/null || true
  rm -rf "$HOME/Applications/Drift.app"
  cp -R "$APP" "$HOME/Applications/"
  APP="$HOME/Applications/Drift.app"
  echo "Installed to ~/Applications/Drift.app"
fi

pkill -x Drift 2>/dev/null || true
sleep 0.3
open "$APP"
echo "Drift is running. Look for its icon in the menu bar."
