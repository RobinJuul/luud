#!/bin/zsh
# Builds Luud.app and installs it to ~/Applications.
# Usage: ./build.sh [--install] [--universal]
#   --install    copy the app to ~/Applications and open it
#   --universal  build one binary for both Apple silicon and Intel (used for releases)
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Luud.app"
DEST="$HOME/Applications/Luud.app"

INSTALL=false
UNIVERSAL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        --universal) UNIVERSAL=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if $UNIVERSAL; then
    # One build per architecture, joined with lipo. Works with the Command Line Tools alone.
    slices=()
    for arch in arm64 x86_64; do
        swift build -c release --arch "$arch"
        slices+=("$(swift build -c release --arch "$arch" --show-bin-path)/Luud")
    done
    lipo -create "${slices[@]}" -output "$APP/Contents/MacOS/Luud"
else
    swift build -c release
    cp .build/release/Luud "$APP/Contents/MacOS/Luud"
fi
cp Support/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
    swift Support/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: enough to run locally and register as a login item.
codesign --force --sign - "$APP"

if $INSTALL; then
    pkill -x Luud 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed to $DEST"
    open "$DEST"
else
    echo "Built $APP (run ./build.sh --install to install and launch)"
fi
