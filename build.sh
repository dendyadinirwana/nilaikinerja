#!/usr/bin/env bash
# Build NilaiKinerja.app from source without Xcode.
#   ./build.sh            debug build
#   ./build.sh release    release build
#   ./build.sh run        build + launch
#   ./build.sh install    build + copy to /Applications
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="NilaiKinerja"
BUNDLE_ID="id.simbang.nilaikinerja"
VERSION="1.0.0"

CONFIG="${1:-debug}"
BUILD_DIR="$ROOT_DIR/.build/$CONFIG"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"

case "$CONFIG" in
  release) SWIFT_FLAGS="--configuration release -Xswiftc -O" ;;
  *)       SWIFT_FLAGS="" ;;
esac

echo "==> swift build ($CONFIG)"
# shellcheck disable=SC2086
(cd "$ROOT_DIR" && swift build $SWIFT_FLAGS 2>&1 | grep -vE "^\[|ld: warning: search path" || true)

BIN_PATH="$(cd "$ROOT_DIR" && swift build $SWIFT_FLAGS --show-bin-path)"

if [[ ! -f "$BIN_PATH/$APP_NAME" ]]; then
  echo "!! binary not found at $BIN_PATH/$APP_NAME" >&2
  exit 1
fi

echo "==> assembling bundle"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$APP_PATH/Contents/MacOS/$APP_NAME"

# Resources: the character page plus the Mood Mates engine it loads. The
# HTML references `mood-mates/...` by relative path, so the directory layout
# has to survive into the bundle.
if [[ -d "$ROOT_DIR/Resources" ]]; then
  cp -R "$ROOT_DIR/Resources/." "$APP_PATH/Contents/Resources/"
fi

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Nilai Kinerja</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Local only. No network access.</string>
</dict>
</plist>
PLIST

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP_PATH" 2>&1 | grep -v "replacing existing" || true

# Verify the signature actually took.
if ! codesign --verify "$APP_PATH" 2>/dev/null; then
  echo "!! codesign verification failed" >&2
  exit 1
fi

echo "==> built: $APP_PATH"
echo "    run:   $APP_PATH/Contents/MacOS/$APP_NAME"
echo "    disk:  $(du -sh "$APP_PATH" | cut -f1)"

case "${2:-}" in
  run)
    echo "==> launching"
    "$APP_PATH/Contents/MacOS/$APP_NAME"
    ;;
  install)
    TARGET="/Applications/$APP_NAME.app"
    echo "==> installing to $TARGET"
    rm -rf "$TARGET"
    ditto "$APP_PATH" "$TARGET"
    echo "    installed: $TARGET"
    ;;
esac
