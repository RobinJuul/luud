import AppKit
import Foundation

struct InstalledApp: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let lastUsed: Date?
    let isAppStore: Bool
    var size: Int64?

    var vendorPrefix: String? { bundleID.flatMap(AppCatalog.vendorPrefix) }
}

struct Leftover: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var selected: Bool = true
    var reason: String?
}

enum AppCatalog {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static func library(_ path: String) -> URL { home.appendingPathComponent("Library").appendingPathComponent(path) }

    // MARK: Installed apps

    static func installedApps() -> [InstalledApp] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        var bundles: [URL] = []
        for root in roots {
            for child in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if child.pathExtension == "app" {
                    bundles.append(child)
                } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    // One level of vendor folders, e.g. /Applications/Microsoft Office/
                    let nested = (try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                    bundles += nested.filter { $0.pathExtension == "app" }
                }
            }
        }

        let ownBundle = Bundle.main.bundleURL.standardizedFileURL
        return bundles.compactMap { url -> InstalledApp? in
            guard url.standardizedFileURL != ownBundle else { return nil }
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            if bundleID?.hasPrefix("com.apple.") == true { return nil }
            let info = bundle?.infoDictionary ?? [:]
            let name = (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            return InstalledApp(
                url: url,
                name: name,
                bundleID: bundleID,
                version: info["CFBundleShortVersionString"] as? String,
                lastUsed: NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date,
                isAppStore: FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt").path)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Leftovers of an installed app

    /// Files an app leaves in ~/Library. Matches on bundle identifier, and on the exact app
    /// name only in folders where apps conventionally use their name.
    static func leftovers(for app: InstalledApp) -> [Leftover] {
        var found: [URL] = []
        let fm = FileManager.default
        let name = app.url.deletingPathExtension().lastPathComponent

        func add(_ url: URL) { if fm.fileExists(atPath: url.path) { found.append(url) } }
        func addMatching(in folder: URL, _ predicate: (String) -> Bool) {
            for child in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            where predicate(child.lastPathComponent) {
                found.append(child)
            }
        }

        for folder in ["Application Support", "Caches", "Logs"] {
            add(library(folder).appendingPathComponent(name))
        }

        if let id = app.bundleID {
            for folder in ["Application Support", "Caches", "Logs", "HTTPStorages", "WebKit", "Application Scripts"] {
                add(library(folder).appendingPathComponent(id))
            }
            add(library("Preferences/\(id).plist"))
            add(library("Saved Application State/\(id).savedState"))
            add(library("HTTPStorages/\(id).binarycookies"))
            add(library("Cookies/\(id).binarycookies"))
            addMatching(in: library("Preferences/ByHost")) { $0.hasPrefix(id + ".") }
            addMatching(in: library("Containers")) { $0 == id || $0.hasPrefix(id + ".") }
            addMatching(in: library("Application Scripts")) { $0.hasPrefix(id + ".") }
            addMatching(in: library("Group Containers")) { $0.hasSuffix("." + id) || $0 == id }
            addMatching(in: library("LaunchAgents")) { $0.hasPrefix(id) && $0.hasSuffix(".plist") }
        }

        var seen = Set<String>()
        return found
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .map { Leftover(url: $0, size: FileSizer.size(of: $0)) }
            .sorted { $0.size > $1.size }
    }

    // MARK: Orphans from apps that are already gone

    static func vendorPrefix(_ bundleID: String) -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return parts.prefix(2).joined(separator: ".").lowercased()
    }

    private static let bundleIDPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9_-]+){2,}$")

    /// Support files whose bundle identifier has no installed app from the same vendor.
    /// Heuristic, so results start unselected.
    static func orphans(installed: [InstalledApp]) -> [Leftover] {
        let installedVendors = Set(installed.compactMap(\.vendorPrefix))
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let fm = FileManager.default

        let folders: [(URL, String)] = [
            (library("Containers"), ""),
            (library("Saved Application State"), ".savedState"),
            (library("Application Support"), ""),
            (library("Caches"), ""),
            (library("Preferences"), ".plist"),
        ]

        var results: [Leftover] = []
        for (folder, suffix) in folders {
            for child in (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                var id = child.lastPathComponent
                if !suffix.isEmpty {
                    guard id.hasSuffix(suffix) else { continue }
                    id = String(id.dropLast(suffix.count))
                }
                let range = NSRange(id.startIndex..., in: id)
                guard bundleIDPattern.firstMatch(in: id, range: range) != nil else { continue }
                let lower = id.lowercased()
                if lower.hasPrefix("com.apple.") || lower.hasPrefix("group.") || lower.hasPrefix("systemgroup.") { continue }
                if running.contains(id) { continue }
                if let vendor = vendorPrefix(id), installedVendors.contains(vendor) { continue }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil { continue }

                let size = FileSizer.size(of: child)
                guard size > 0 else { continue }
                results.append(Leftover(url: child, size: size, selected: false,
                                        reason: "No installed app from \(vendorPrefix(id) ?? id)"))
            }
        }
        return results.sorted { $0.size > $1.size }
    }
}
