import AppKit
import Foundation

struct LaunchItem: Identifiable, Hashable {
    enum Scope: String, CaseIterable {
        case userAgent = "Your Launch Agents"
        case globalAgent = "Launch Agents (all users)"
        case daemon = "Launch Daemons (system)"

        var folder: URL {
            switch self {
            case .userAgent: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
            case .globalAgent: URL(fileURLWithPath: "/Library/LaunchAgents")
            case .daemon: URL(fileURLWithPath: "/Library/LaunchDaemons")
            }
        }

        /// launchctl domain the service runs in.
        var domain: String {
            self == .daemon ? "system" : "gui/\(getuid())"
        }

        var needsAdmin: Bool { self == .daemon }
    }

    var id: URL { url }
    let url: URL
    let label: String
    let program: String?
    let scope: Scope
    let runsAtLoad: Bool
    let keepsAlive: Bool
    var isDisabled: Bool

    var serviceTarget: String { "\(scope.domain)/\(label)" }
}

enum MaintenanceTask: String, CaseIterable, Identifiable {
    case freeRAM, flushDNS, thinSnapshots, reindexSpotlight, rebuildLaunchServices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeRAM: "Free up RAM"
        case .flushDNS: "Flush DNS cache"
        case .thinSnapshots: "Thin Time Machine snapshots"
        case .reindexSpotlight: "Reindex Spotlight"
        case .rebuildLaunchServices: "Rebuild Launch Services"
        }
    }

    var detail: String {
        switch self {
        case .freeRAM: "Purges inactive memory and disk cache. Useful before a heavy task."
        case .flushDNS: "Fixes websites that won't load after a network or DNS change."
        case .thinSnapshots: "Removes local Time Machine snapshots that hold \"purgeable\" disk space."
        case .reindexSpotlight: "Rebuilds the search index when Spotlight results are missing or wrong. Takes a while."
        case .rebuildLaunchServices: "Fixes duplicate entries in \"Open With\" and wrong default apps."
        }
    }

    var icon: String {
        switch self {
        case .freeRAM: "memorychip"
        case .flushDNS: "network"
        case .thinSnapshots: "clock.arrow.circlepath"
        case .reindexSpotlight: "magnifyingglass"
        case .rebuildLaunchServices: "square.stack.3d.up"
        }
    }

    var needsAdmin: Bool { self != .rebuildLaunchServices }

    var command: String {
        switch self {
        case .freeRAM: "/usr/sbin/purge"
        case .flushDNS: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        case .thinSnapshots: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
        case .reindexSpotlight: "/usr/bin/mdutil -E /"
        case .rebuildLaunchServices:
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"
        }
    }
}

@MainActor
final class PerformanceModel: ObservableObject {
    @Published private(set) var items: [LaunchItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var runningTask: MaintenanceTask?
    @Published private(set) var busyItem: LaunchItem.ID?
    @Published var message: String?

    func load() async {
        isLoading = true
        items = await Task.detached { Self.readLaunchItems() }.value
        isLoading = false
    }

    func run(_ task: MaintenanceTask) async {
        runningTask = task
        let result = await Task.detached {
            task.needsAdmin ? Shell.runAsAdmin(task.command) : Shell.run("/bin/sh", ["-c", task.command])
        }.value
        runningTask = nil
        if result.wasCancelled {
            message = "\(task.title): cancelled."
        } else if result.succeeded {
            message = "\(task.title): done."
        } else {
            message = "\(task.title) failed: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    /// Disabling is reversible: launchd remembers the override and the plist stays in place.
    func setDisabled(_ item: LaunchItem, disabled: Bool) async {
        busyItem = item.id
        let path = Shell.quote(item.url.path)
        let target = Shell.quote(item.serviceTarget)
        let domain = Shell.quote(item.scope.domain)
        let command = disabled
            ? "/bin/launchctl bootout \(domain) \(path) 2>/dev/null; /bin/launchctl disable \(target)"
            : "/bin/launchctl enable \(target); /bin/launchctl bootstrap \(domain) \(path) 2>/dev/null; true"
        let result = await Task.detached {
            item.scope.needsAdmin ? Shell.runAsAdmin(command) : Shell.run("/bin/sh", ["-c", command])
        }.value
        busyItem = nil
        if result.succeeded {
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].isDisabled = disabled }
            message = "\(item.label) \(disabled ? "disabled" : "enabled")."
        } else if !result.wasCancelled {
            message = "Couldn't change \(item.label): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
    }

    /// Removes a launch agent from your own LaunchAgents folder (moves the plist to the Trash).
    func remove(_ item: LaunchItem) async {
        guard item.scope == .userAgent else { return }
        busyItem = item.id
        _ = await Task.detached {
            Shell.run("/bin/launchctl", ["bootout", item.scope.domain, item.url.path])
        }.value
        do {
            _ = try await NSWorkspace.shared.moveToTrash([item.url])
            items.removeAll { $0.id == item.id }
            message = "Removed \(item.label)."
        } catch {
            message = "Couldn't remove \(item.label): \(error.localizedDescription)"
        }
        busyItem = nil
    }

    nonisolated private static func readLaunchItems() -> [LaunchItem] {
        var disabledByDomain: [String: Set<String>] = [:]
        func disabledLabels(_ domain: String) -> Set<String> {
            if let cached = disabledByDomain[domain] { return cached }
            let output = Shell.run("/bin/launchctl", ["print-disabled", domain]).output
            let regex = try! NSRegularExpression(pattern: "\"([^\"]+)\"\\s*=>\\s*(disabled|true)")
            let labels = Set(regex.matches(in: output, range: NSRange(output.startIndex..., in: output)).compactMap {
                Range($0.range(at: 1), in: output).map { String(output[$0]) }
            })
            disabledByDomain[domain] = labels
            return labels
        }

        var items: [LaunchItem] = []
        for scope in LaunchItem.Scope.allCases {
            let plists = ((try? FileManager.default.contentsOfDirectory(at: scope.folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "plist" }
            for url in plists {
                guard let plist = NSDictionary(contentsOf: url) as? [String: Any] else { continue }
                let label = plist["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = plist["Program"] as? String ?? (plist["ProgramArguments"] as? [String])?.first
                let keepAlive = (plist["KeepAlive"] as? Bool) ?? (plist["KeepAlive"] is [String: Any])
                items.append(LaunchItem(
                    url: url,
                    label: label,
                    program: program,
                    scope: scope,
                    runsAtLoad: plist["RunAtLoad"] as? Bool ?? false,
                    keepsAlive: keepAlive,
                    isDisabled: disabledLabels(scope.domain).contains(label) || plist["Disabled"] as? Bool == true
                ))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
