#!/bin/sh
# Builds mdv.app. Needs Xcode command line tools.
#   ./build.sh                          build + install to /Applications
#   ./build.sh --no-install             build only (build/mdv.app)
#   ./build.sh --dist                   build, sign, notarize (if set up), zip, install
#   options: --version 1.2  --build 7   stamp Info.plist (release.sh passes these)
set -e
cd "$(dirname "$0")"
. ./release.conf
APP=build/mdv.app
ARCH=$(uname -m)
INSTALL=1; DIST=0; VERSION=""; BUILDNUM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-install) INSTALL=0 ;;
    --dist) DIST=1 ;;
    --version) VERSION="$2"; shift ;;
    --build) BUILDNUM="$2"; shift ;;
  esac
  shift
done
[ -n "$VERSION" ] || VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); [ -n "$VERSION" ] || VERSION="0.0"
[ -n "$BUILDNUM" ] || BUILDNUM=$(cat build-number 2>/dev/null || echo 0)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -module-name mdv -target "$ARCH-apple-macos13.0" \
  -framework Cocoa -framework WebKit -framework UniformTypeIdentifiers \
  -o "$APP/Contents/MacOS/mdv" Sources/*.swift
cp Resources/viewer.html "$APP/Contents/Resources/"
cp -R Resources/vendor "$APP/Contents/Resources/vendor"
cp -R Resources/skill "$APP/Contents/Resources/skill"
cp Resources/Info.plist "$APP/Contents/"

# Stamp version + update feed into the bundle's Info.plist
PB=/usr/libexec/PlistBuddy; PL="$APP/Contents/Info.plist"
$PB -c "Set :CFBundleShortVersionString $VERSION" "$PL"
$PB -c "Set :CFBundleVersion $BUILDNUM" "$PL"
$PB -c "Add :MDVUpdateFeed string https://github.com/$RELEASES_REPO/releases/latest/download/latest.json" "$PL"
$PB -c "Add :MDVReleasesPage string https://github.com/$RELEASES_REPO/releases/latest" "$PL"

xcrun swift Resources/icon.swift build/mdv.iconset
iconutil -c icns build/mdv.iconset -o "$APP/Contents/Resources/mdv.icns"

# Sign with the Developer ID cert if one is in the keychain, else ad-hoc (local use only, no self-update).
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')
if [ -n "$SIGN_ID" ]; then
  TEAM=$(echo "$SIGN_ID" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
  $PB -c "Add :MDVTeamID string $TEAM" "$PL"
  codesign --force --deep --options runtime --timestamp -s "$SIGN_ID" "$APP"
  echo "signed: $SIGN_ID"
else
  codesign -s - --force "$APP" >/dev/null 2>&1 || true
  echo "signed: ad-hoc (no Developer ID cert found)"
fi
echo "version: $VERSION (build $BUILDNUM)"

if [ "$DIST" = 1 ]; then
  ditto -c -k --keepParent "$APP" build/mdv.zip
  if [ -n "$SIGN_ID" ] && xcrun notarytool history --keychain-profile mdv >/dev/null 2>&1; then
    echo "notarizing (this takes a minute or two)..."
    xcrun notarytool submit build/mdv.zip --keychain-profile mdv --wait
    xcrun stapler staple "$APP"
    rm -f build/mdv.zip
    ditto -c -k --keepParent "$APP" build/mdv.zip
    echo "notarized + stapled"
  else
    echo "not notarized: friends will need right-click → Open once (see README to set up notarization)"
  fi
  echo "zip: build/mdv.zip ($(du -h build/mdv.zip | cut -f1))"
fi
if [ "$INSTALL" = 1 ]; then
  rm -rf /Applications/mdv.app
  cp -R "$APP" /Applications/mdv.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/mdv.app
  echo "installed /Applications/mdv.app"
fi
