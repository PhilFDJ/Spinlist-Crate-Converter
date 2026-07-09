#!/bin/bash
# build.sh — compile, bundle, sign, and package Spinlist Crate Converter.
#
# Run on macOS with Xcode command line tools installed (xcode-select --install).
# Configure your signing identity below (or via env vars), then:
#     ./build.sh
#
# Output:
#   build/Spinlist Crate Converter.app   (signed)
#   dist/Spinlist Crate Converter.dmg    (signed, NOT yet notarized)
#
# After this, run ./notarize.sh to notarize + staple for public distribution.
set -euo pipefail
cd "$(dirname "$0")"
# ---- CONFIG ---------------------------------------------------------------
# Your Developer ID Application identity. Find it with:
#     security find-identity -v -p codesigning
# It looks like: "Developer ID Application: Phil Freeman (ABCDE12345)"
DEV_ID="${DEV_ID:-Developer ID Application: YOUR NAME (TEAMID)}"
APP_NAME="Spinlist Crate Converter"
MIN_MACOS="12.0"
# ---------------------------------------------------------------------------
BUILD="build"
DIST="dist"
APP="$BUILD/$APP_NAME.app"
rm -rf "$BUILD" "$DIST"
mkdir -p "$BUILD" "$DIST"
echo "==> Compiling (universal binary)…"
BUILT=()
for arch in arm64 x86_64; do
  if xcrun swiftc -parse-as-library -O \
        -target ${arch}-apple-macos${MIN_MACOS} \
        src/SpinlistCrateConverter.swift \
        -o "$BUILD/scc-${arch}" 2>"$BUILD/build-${arch}.log"; then
    BUILT+=("$BUILD/scc-${arch}")
    echo "    built ${arch}"
  else
    echo "    (skipped ${arch} — see $BUILD/build-${arch}.log)"
  fi
done
if [ ${#BUILT[@]} -eq 0 ]; then
  echo "ERROR: compilation failed for all architectures."; cat "$BUILD"/build-*.log; exit 1
fi
lipo -create -output "$BUILD/SpinlistCrateConverter" "${BUILT[@]}"
echo "==> Assembling app bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/SpinlistCrateConverter" "$APP/Contents/MacOS/SpinlistCrateConverter"
cp assets/Info.plist              "$APP/Contents/Info.plist"
cp assets/AppIcon.icns            "$APP/Contents/Resources/AppIcon.icns"
cp assets/dropmark.png            "$APP/Contents/Resources/dropmark.png"
chmod +x "$APP/Contents/MacOS/SpinlistCrateConverter"
if [ "$DEV_ID" = "Developer ID Application: YOUR NAME (TEAMID)" ]; then
  echo
  echo "!! DEV_ID is not set. Edit build.sh (or run: export DEV_ID=\"Developer ID Application: … (TEAMID)\")"
  echo "!! Leaving the app UNSIGNED so you can test it locally (right-click > Open)."
  SIGNED=0
else
  echo "==> Codesigning with hardened runtime…"
  codesign --force --options runtime --timestamp \
           --sign "$DEV_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  SIGNED=1
fi
echo "==> Building DMG…"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
        -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
if [ "$SIGNED" = "1" ]; then
  codesign --force --timestamp --sign "$DEV_ID" "$DIST/$APP_NAME.dmg"
fi
echo
echo "Done."
echo "  App:  $APP"
echo "  DMG:  $DIST/$APP_NAME.dmg"
if [ "$SIGNED" = "1" ]; then
  echo
  echo "Next: notarize for public distribution ->  ./notarize.sh"
else
  echo
  echo "Set DEV_ID and re-run to produce a signed build before notarizing."
fi
