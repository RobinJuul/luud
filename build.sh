#!/bin/zsh
# Builds Luud.app and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Luud.app"
DEST="$HOME/Applications/Luud.app"

swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Luud "$APP/Contents/MacOS/Luud"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
    swift Support/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally and register as a login item.
codesign --force --sign - "$APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Luud 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed to $DEST"
    open "$DEST"
else
    echo "Built $APP (run ./build.sh --install to install and launch)"
fi
