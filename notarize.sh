#!/bin/bash
# notarize.sh — notarize + staple Spinlist Crate Converter for public download.
#
# Prerequisite (one time): store your notarization credentials in the keychain
# so this script never sees your password:
#
#   xcrun notarytool store-credentials "spinlist-notary" \
#       --apple-id "you@example.com" \
#       --team-id "TEAMID" \
#       --password "app-specific-password"
#
#   (Create the app-specific password at https://account.apple.com > Sign-In &
#    Security > App-Specific Passwords. It is NOT your normal Apple ID password.)
#
# Then run:  ./notarize.sh
#
# This notarizes the .app, staples it, rebuilds the DMG around the stapled app,
# notarizes the DMG, and staples that too — so both work offline after download.
set -euo pipefail
cd "$(dirname "$0")"
DEV_ID="${DEV_ID:-Developer ID Application: YOUR NAME (TEAMID)}"
PROFILE="${NOTARY_PROFILE:-spinlist-notary}"
APP_NAME="Spinlist Crate Converter"
APP="build/$APP_NAME.app"
DIST="dist"
if [ ! -d "$APP" ]; then
  echo "ERROR: $APP not found. Run ./build.sh first (with DEV_ID set)."; exit 1
fi
if [ "$DEV_ID" = "Developer ID Application: YOUR NAME (TEAMID)" ]; then
  echo "ERROR: set DEV_ID first (same value you used in build.sh)."; exit 1
fi
echo "==> Notarizing the app…"
APPZIP="build/$APP_NAME.zip"
rm -f "$APPZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$APPZIP"
xcrun notarytool submit "$APPZIP" --keychain-profile "$PROFILE" --wait
echo "==> Stapling the app…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
echo "==> Rebuilding DMG around the stapled app…"
STAGE="build/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DIST/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" \
        -ov -format UDZO "$DIST/$APP_NAME.dmg" >/dev/null
codesign --force --timestamp --sign "$DEV_ID" "$DIST/$APP_NAME.dmg"
echo "==> Notarizing the DMG…"
xcrun notarytool submit "$DIST/$APP_NAME.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DIST/$APP_NAME.dmg"
xcrun stapler validate "$DIST/$APP_NAME.dmg"
echo
echo "Notarized + stapled:"
echo "  $DIST/$APP_NAME.dmg"
echo "Verify Gatekeeper acceptance:"
echo "  spctl -a -t open --context context:primary-signature -vvv \"$DIST/$APP_NAME.dmg\""
echo
echo "This DMG is ready to upload to your website."
