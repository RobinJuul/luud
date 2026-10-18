// Prints the window number of Luud's main window ("main") or its menu panel preview ("menu"),
// for `screencapture -l`. Used by Scripts/screenshots.sh.
import CoreGraphics

let kind = CommandLine.arguments.dropFirst().first ?? "main"
let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
let candidates = windows.compactMap { window -> (id: Int, width: Double, height: Double)? in
    guard window["kCGWindowOwnerName"] as? String == "Luud", window["kCGWindowLayer"] as? Int == 0,
          let id = window["kCGWindowNumber"] as? Int,
          let bounds = window["kCGWindowBounds"] as? [String: Any],
          let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double,
          height > 200 else { return nil }
    return (id, width, height)
}
let pick = kind == "menu"
    ? candidates.filter { $0.width < 420 }.first
    : candidates.max { $0.width * $0.height < $1.width * $1.height }
if let pick { print(pick.id) } else { exit(1) }
