import Foundation

/// Optional launch arguments, used by Scripts/screenshots.sh to stage README screenshots.
/// Pass them as `open Luud.app --args -LuudSection dashboard -LuudAutoScan YES`.
/// Arguments land in UserDefaults' volatile argument domain, so nothing is stored.
enum LaunchOptions {
    private static let defaults = UserDefaults.standard

    /// Screen to open on, by AppSection raw value (e.g. "dashboard", "cleanup").
    static var section: AppSection? { defaults.string(forKey: "LuudSection").flatMap(AppSection.init) }

    /// Start the scan for the opening screen right away.
    static var autoScan: Bool { defaults.bool(forKey: "LuudAutoScan") }

    /// Folder Space Lens maps on launch.
    static var spaceLensRoot: URL? { defaults.string(forKey: "LuudSpaceLensRoot").map { URL(fileURLWithPath: $0) } }

    /// Bundle identifier the Uninstaller selects once apps are listed.
    static var uninstallerApp: String? { defaults.string(forKey: "LuudSelectApp") }

    /// Show the menu bar panel in a regular window (the real one only opens on click).
    static var menuPreview: Bool { defaults.bool(forKey: "LuudMenuPreview") }
}
