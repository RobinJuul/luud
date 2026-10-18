#!/bin/zsh
# Regenerates the README screenshots in Design/screenshots by launching Luud in staged states.
# Needs Screen Recording permission for your terminal app. Takes about two minutes; Luud's
# windows will open and close on screen while it runs. Scans are read-only: nothing is removed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$HOME/Applications/Luud.app"
OUT="Design/screenshots"
HELPER="build/window-id"
mkdir -p "$OUT" build
[[ -d "$APP" ]] || { echo "Install Luud first: ./build.sh --install"; exit 1; }
[[ -x "$HELPER" ]] || swiftc -O -o "$HELPER" Scripts/window-id.swift

ONLY="${1:-}"   # optional: capture just one screenshot, e.g. ./Scripts/screenshots.sh menu-bar

# shoot <name> <seconds to wait> <main|menu> <launch arguments…>
shoot() {
    local name=$1 wait=$2 kind=$3
    shift 3
    [[ -n "$ONLY" && "$name" != "$ONLY" ]] && return 0
    pkill -x Luud 2>/dev/null || true
    while pgrep -x Luud >/dev/null; do sleep 0.2; done
    open -n "$APP" --args "$@"
    # Wait for the window to appear, then give scans and animations time to settle.
    local id="" tries=0
    until id=$("$HELPER" "$kind" 2>/dev/null); do
        (( ++tries > 50 )) && { echo "  couldn't find the $kind window for $name"; return 1; }
        sleep 0.2
    done
    sleep "$wait"
    screencapture -x -o -l "$id" "$OUT/$name.png"
    echo "  $OUT/$name.png"
}

echo "Capturing screenshots…"
shoot smart-care  25 main -LuudSection smartCare -LuudAutoScan YES
shoot dashboard   65 main -LuudSection dashboard
shoot system-junk 20 main -LuudSection cleanup -LuudAutoScan YES
shoot uninstaller 15 main -LuudSection uninstaller -LuudSelectApp "${LUUD_SCREENSHOT_APP:-com.spotify.client}"
shoot space-lens  20 main -LuudSection spaceLens -LuudSpaceLensRoot /Applications
shoot menu-bar    65 menu -LuudMenuPreview YES

pkill -x Luud 2>/dev/null || true
sleep 1
open "$APP"
echo "Done."
