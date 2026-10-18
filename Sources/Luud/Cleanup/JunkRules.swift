import Foundation

struct JunkCandidate {
    let url: URL
    var selected: Bool = true
    var note: String?
}

/// How removed items are disposed of. Regenerable data is deleted outright;
/// anything a person might still want goes to the Trash so it can be restored.
enum Disposal {
    case delete
    case moveToTrash
}

struct JunkContext {
    let runningBundleIDs: Set<String>
}

struct JunkDefinition {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let disposal: Disposal
    let candidates: (JunkContext) throws -> [JunkCandidate]
}

enum JunkRules {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func library(_ path: String) -> URL { home.appendingPathComponent("Library").appendingPathComponent(path) }

    /// Caches that belong to system services where deleting can sign you out or break sync.
    static let protectedCaches: Set<String> = [
        "CloudKit", "com.apple.bird", "com.apple.HomeKit", "com.apple.containermanagerd",
        "com.apple.akd", "FamilyCircle", "com.apple.ap.adprivacyd", "com.apple.findmy.fmipcore",
        "com.apple.Safari.SafeBrowsing", "com.apple.nsurlsessiond", "com.apple.passd",
        "com.apple.iCloudHelper", Bundle.main.bundleIdentifier ?? "com.robinjuul.Luud",
    ]

    static let all: [JunkDefinition] = [
        JunkDefinition(
            id: "user-caches", title: "User Caches",
            subtitle: "Temporary files apps rebuild automatically",
            icon: "shippingbox", disposal: .delete
        ) { context in
            try children(of: library("Caches"))
                .filter { !protectedCaches.contains($0.lastPathComponent) }
                .map { url in
                    let inUse = context.runningBundleIDs.contains(url.lastPathComponent)
                    return JunkCandidate(url: url, selected: !inUse, note: inUse ? "App is running — quit it first for a clean result" : nil)
                }
        },
        JunkDefinition(
            id: "user-logs", title: "Logs & Crash Reports",
            subtitle: "Diagnostic logs written by apps and macOS",
            icon: "doc.text.magnifyingglass", disposal: .delete
        ) { _ in
            try children(of: library("Logs")).map { JunkCandidate(url: $0) }
        },
        JunkDefinition(
            id: "xcode", title: "Xcode Junk",
            subtitle: "Derived data, old device support files and simulator caches",
            icon: "hammer", disposal: .delete
        ) { _ in
            let developer = library("Developer")
            var items: [JunkCandidate] = []
            items += try children(of: developer.appendingPathComponent("Xcode/DerivedData")).map { JunkCandidate(url: $0) }
            for platform in ["iOS", "watchOS", "tvOS", "visionOS"] {
                items += try children(of: developer.appendingPathComponent("Xcode/\(platform) DeviceSupport"))
                    .map { JunkCandidate(url: $0, note: "\(platform) device support — re-downloaded when a device connects") }
            }
            items += existing([developer.appendingPathComponent("CoreSimulator/Caches")]).map { JunkCandidate(url: $0) }
            items += try children(of: developer.appendingPathComponent("Xcode/Archives"))
                .map { JunkCandidate(url: $0, selected: false, note: "Build archive — keep it if you may need to re-submit or symbolicate") }
            return items
        },
        JunkDefinition(
            id: "dev-caches", title: "Developer Caches",
            subtitle: "Package manager download caches (npm, Gradle, Cargo, conda…)",
            icon: "terminal", disposal: .delete
        ) { _ in
            let paths: [(String, Bool, String?)] = [
                (".npm/_cacache", true, "npm cache"),
                (".gradle/caches", true, "Gradle cache"),
                (".cargo/registry/cache", true, "Cargo crate downloads"),
                (".yarn/berry/cache", true, "Yarn cache"),
                ("Library/pnpm/store", true, "pnpm store — projects re-link on next install"),
                (".cocoapods/repos", false, "CocoaPods spec repos"),
                (".m2/repository", false, "Maven repository — large re-download"),
                ("anaconda3/pkgs", true, "conda package cache"),
                ("opt/anaconda3/pkgs", true, "conda package cache"),
                ("miniconda3/pkgs", true, "conda package cache"),
            ]
            return paths.compactMap { path, selected, note in
                let url = home.appendingPathComponent(path)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return JunkCandidate(url: url, selected: selected, note: note)
            }
        },
        JunkDefinition(
            id: "installers", title: "Installers in Downloads",
            subtitle: "Disk images and packages you've already installed",
            icon: "arrow.down.app", disposal: .moveToTrash
        ) { _ in
            let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]
            return try children(of: home.appendingPathComponent("Downloads"))
                .filter { extensions.contains($0.pathExtension.lowercased()) }
                .map { JunkCandidate(url: $0) }
        },
        JunkDefinition(
            id: "mail", title: "Mail Attachments",
            subtitle: "Local copies of attachments you opened in Mail",
            icon: "paperclip", disposal: .moveToTrash
        ) { _ in
            try children(of: library("Containers/com.apple.mail/Data/Library/Mail Downloads")).map { JunkCandidate(url: $0) }
        },
        JunkDefinition(
            id: "trash", title: "Trash",
            subtitle: "Items already in your Trash",
            icon: "trash", disposal: .delete
        ) { _ in
            try children(of: home.appendingPathComponent(".Trash")).map { JunkCandidate(url: $0) }
        },
    ]

    /// Direct children of a folder. A missing folder is empty; a permission problem is thrown.
    static func children(of url: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try FileManager.default
            .contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            .filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
    }

    static func existing(_ urls: [URL]) -> [URL] {
        urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
