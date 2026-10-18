#!/bin/zsh
# Builds a universal Luud.app and packages it for release in dist/:
#   Luud-<version>.dmg   disk image with an Applications shortcut to drag onto
#   Luud-<version>.zip   the app on its own
#   SHA256SUMS           checksums for both
# The version comes from CFBundleShortVersionString in Support/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)
APP="build/Luud.app"
DIST="dist"
STAGE="build/dmg"

./build.sh --universal
codesign --verify --strict "$APP"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Luud")"

rm -rf "$DIST" "$STAGE"
mkdir -p "$DIST" "$STAGE"

ditto -c -k --keepParent "$APP" "$DIST/Luud-$VERSION.zip"

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Luud $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DIST/Luud-$VERSION.dmg"

(cd "$DIST" && shasum -a 256 "Luud-$VERSION.dmg" "Luud-$VERSION.zip" > SHA256SUMS)
echo "Packaged Luud $VERSION:"
ls -lh "$DIST"
