#!/bin/bash
# Builds Sotto.app from source and installs it into /Applications.
# Run:  bash "scripts/build_app.sh"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Sotto.app"

if [ ! -f "$ROOT/vendor/whisper.cpp/build/src/libwhisper.a" ]; then
  bash "$ROOT/scripts/setup_whisper.sh"
fi

echo "==> Compiling Sotto..."
cd "$ROOT/Sotto"
swift build -c release 2>&1 | grep -v 'ld: warning' || true
test -x "$ROOT/Sotto/.build/release/Sotto"

echo "==> Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Sotto/.build/release/Sotto" "$APP/Contents/MacOS/Sotto"
cp "$ROOT/scripts/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/scripts/AppIcon.icns" ]; then
  cp "$ROOT/scripts/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Signing (local ad-hoc signature)..."
codesign --force --sign - "$APP"

echo "==> Installing to /Applications..."
if rm -rf /Applications/Sotto.app 2>/dev/null && cp -R "$APP" /Applications/ 2>/dev/null; then
  DEST="/Applications/Sotto.app"
else
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/Sotto.app"
  cp -R "$APP" "$HOME/Applications/"
  DEST="$HOME/Applications/Sotto.app"
fi
echo "==> Installed: $DEST"
echo "Done. Note: after rebuilding, macOS treats it as a new app —"
echo "re-grant Input Monitoring and Accessibility if dictation stops working."
