import AppKit
import Foundation

@MainActor
final class UninstallerModel: ObservableObject {
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var selection: InstalledApp.ID?
    @Published var leftovers: [Leftover] = []
    @Published private(set) var isLoadingLeftovers = false
    @Published var orphans: [Leftover] = []
    @Published private(set) var isLoadingOrphans = false
    @Published var message: String?

    private var leftoverTask: Task<Void, Never>?

    var selectedApp: InstalledApp? { apps.first { $0.id == selection } }

    /// Apps not opened for at least this long count as unused.
    static let unusedInterval: TimeInterval = 180 * 24 * 3600

    var unusedApps: [InstalledApp] {
        let cutoff = Date().addingTimeInterval(-Self.unusedInterval)
        return apps.filter { ($0.lastUsed ?? .distantPast) < cutoff }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        apps = await Task.detached { AppCatalog.installedApps() }.value
        isLoading = false
        hasLoaded = true

        // Sizes take a while for big apps; fill them in as they arrive.
        await withTaskGroup(of: (URL, Int64).self) { group in
            for app in apps {
                group.addTask { (app.url, FileSizer.size(of: app.url)) }
            }
            for await (url, size) in group {
                if let index = apps.firstIndex(where: { $0.url == url }) { apps[index].size = size }
            }
        }
    }

    func loadLeftovers() {
        leftoverTask?.cancel()
        leftovers = []
        isLoadingLeftovers = false
        guard let app = selectedApp else { return }
        isLoadingLeftovers = true
        leftoverTask = Task {
            let found = await Task.detached { AppCatalog.leftovers(for: app) }.value
            guard !Task.isCancelled, selection == app.id else { return }
            leftovers = found
            isLoadingLeftovers = false
        }
    }

    func loadOrphans() async {
        isLoadingOrphans = true
        let installed = apps
        orphans = await Task.detached { AppCatalog.orphans(installed: installed) }.value
        isLoadingOrphans = false
    }

    func uninstall(_ app: InstalledApp) async {
        if let id = app.bundleID {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                running.terminate()
            }
            for _ in 0..<20 where !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
                message = "\(app.name) is still running. Quit it and try again."
                return
            }
        }

        let urls = [app.url] + leftovers.filter(\.selected).map(\.url)
        var trashError: Error?
        do {
            _ = try await NSWorkspace.shared.moveToTrash(urls)
        } catch {
            trashError = error
        }
        if FileManager.default.fileExists(atPath: app.url.path) {
            // Apps installed by an admin package can't be moved by us directly; Finder asks for a password.
            let script = "tell application \"Finder\" to delete (POSIX file \(appleScriptString(app.url.path)))"
            var errorInfo: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
            if FileManager.default.fileExists(atPath: app.url.path) {
                let reason = trashError?.localizedDescription ?? (errorInfo?[NSAppleScript.errorMessage] as? String) ?? "permission denied"
                message = "Couldn't remove \(app.name): \(reason)"
                return
            }
            if trashError != nil {
                _ = try? await NSWorkspace.shared.moveToTrash(Array(urls.dropFirst()))
            }
        }

        let freed = (app.size ?? 0) + leftovers.filter(\.selected).reduce(0) { $0 + $1.size }
        message = "Moved \(app.name) and its files to the Trash (\(Fmt.bytes(freed)))."
        apps.removeAll { $0.id == app.id }
        selection = nil
        leftovers = []
    }

    func removeOrphans() async {
        let urls = orphans.filter(\.selected).map(\.url)
        guard !urls.isEmpty else { return }
        let moved = (try? await NSWorkspace.shared.moveToTrash(urls)) ?? [:]
        let movedSet = Set(moved.keys)
        let freed = orphans.filter { movedSet.contains($0.url) }.reduce(0) { $0 + $1.size }
        orphans.removeAll { movedSet.contains($0.url) }
        message = "Moved \(movedSet.count) leftover items to the Trash (\(Fmt.bytes(freed)))."
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
