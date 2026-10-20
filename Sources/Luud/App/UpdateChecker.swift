import AppKit
import Foundation
import UserNotifications

/// Asks GitHub once a day whether a newer Luud has been released. This is the only network
/// request Luud makes; it sends nothing about the person or their Mac, and can be turned off.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var available: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var lastError: String?

    static let enabledKey = "checkForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let notifiedKey = "notifiedUpdateVersion"
    private static let latestReleaseAPI = URL(string: "https://api.github.com/repos/RobinJuul/luud/releases/latest")!
    private static let releasesPage = URL(string: "https://github.com/RobinJuul/luud/releases/latest")!
    private static let interval: TimeInterval = 24 * 3600

    private var timer: Timer?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date

        // Staged screenshots: show an update without asking GitHub.
        if let version = LaunchOptions.pretendUpdate {
            available = Release(version: version, url: Self.releasesPage)
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(10))   // stay out of the way while the app starts
            await checkIfDue()
        }
        // Wake hourly; a check only runs once a day has passed since the last one.
        let timer = Timer(timeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.checkIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkIfDue() async {
        guard isEnabled else { return }
        if let lastChecked, Date().timeIntervalSince(lastChecked) < Self.interval { return }
        await check()
    }

    func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: Self.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Luud/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: Self.lastCheckKey)
            lastError = nil

            let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
            if !release.draft, !release.prerelease, Self.isNewer(version, than: currentVersion) {
                available = Release(version: version, url: release.html_url)
                notifyOnce(about: version)
            } else {
                available = nil
            }
        } catch {
            lastError = "Couldn't reach GitHub. Luud will try again later."
        }
    }

    func openDownloadPage() {
        NSWorkspace.shared.open(available?.url ?? Self.releasesPage)
    }

    /// Compares dotted version numbers: 0.1.10 is newer than 0.1.9.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// One notification per new version, so people who never open the menu still hear about it.
    private func notifyOnce(about version: String) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.notifiedKey) != version else { return }
        defaults.set(version, forKey: Self.notifiedKey)

        let content = UNMutableNotificationContent()
        content.title = "Luud \(version) is available"
        content.body = "Open Luud's menu or Settings to see what's new and download it."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "update-\(version)", content: content, trigger: nil)
        )
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: URL
        let draft: Bool
        let prerelease: Bool
    }
}
