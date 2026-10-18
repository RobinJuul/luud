import AppKit
import SwiftUI
import UserNotifications

@main
struct LuudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var stats = SystemStats()
    @StateObject private var router = Router.shared
    @StateObject private var cleanup = CleanupModel()
    @StateObject private var uninstaller = UninstallerModel()
    @StateObject private var spaceLens = SpaceLensModel()
    @StateObject private var largeFiles = LargeFilesModel()
    @StateObject private var performance = PerformanceModel()

    init() {
        SettingsMigration.run()
    }

    var body: some Scene {
        Window("Luud", id: Router.mainWindowID) {
            MainView()
                .environmentObject(stats)
                .environmentObject(router)
                .environmentObject(cleanup)
                .environmentObject(uninstaller)
                .environmentObject(spaceLens)
                .environmentObject(largeFiles)
                .environmentObject(performance)
        }
        .defaultSize(width: 1160, height: 780)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(stats)
                .environmentObject(router)
        } label: {
            MenuBarLabel(stats: stats, router: router)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Started by "Open at Login": stay in the menu bar instead of popping the window open.
        if LaunchContext.isLoginLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for window in NSApp.windows where window.identifier?.rawValue.hasPrefix(Router.mainWindowID) == true {
                    window.close()
                }
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { Router.shared.openMain() }
        return true
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case smartCare, dashboard, cleanup, uninstaller, spaceLens, largeFiles, performance, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .dashboard: "Live Dashboard"
        case .cleanup: "System Junk"
        case .uninstaller: "Uninstaller"
        case .spaceLens: "Space Lens"
        case .largeFiles: "Large Files"
        case .performance: "Performance"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .smartCare: "sparkles"
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .cleanup: "trash"
        case .uninstaller: "xmark.app"
        case .spaceLens: "circle.hexagongrid"
        case .largeFiles: "doc.badge.ellipsis"
        case .performance: "bolt"
        case .settings: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .smartCare: .pink
        case .dashboard: .blue
        case .cleanup: .green
        case .uninstaller: .orange
        case .spaceLens: .purple
        case .largeFiles: .teal
        case .performance: .yellow
        case .settings: .gray
        }
    }
}

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    static let mainWindowID = "main"

    @Published var selection: AppSection? = .smartCare
    /// Captured from the always-present menu bar label so the window can be opened from anywhere.
    var openWindowAction: OpenWindowAction?

    func openMain(_ section: AppSection? = nil) {
        if let section { selection = section }
        NSApp.setActivationPolicy(.regular)
        openWindowAction?(id: Self.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

enum LaunchContext {
    /// True when the app started within two minutes of the console user logging in.
    static let isLoginLaunch: Bool = {
        setutxent()
        defer { endutxent() }
        var latestLogin: Date?
        while let entry = getutxent() {
            let record = entry.pointee
            guard Int32(record.ut_type) == USER_PROCESS else { continue }
            let line = withUnsafeBytes(of: record.ut_line) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            guard line == "console" else { continue }
            let date = Date(timeIntervalSince1970: TimeInterval(record.ut_tv.tv_sec))
            if latestLogin.map({ date > $0 }) ?? true { latestLogin = date }
        }
        guard let latestLogin else { return false }
        return Date().timeIntervalSince(latestLogin) < 120
    }()
}

/// The app was called MacSweep before it became Luud. Settings live under the bundle id,
/// so carry them across once.
enum SettingsMigration {
    private static let oldDomain = "com.robinjuul.MacSweep"
    private static let doneKey = "migratedFromMacSweep"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        if let old = UserDefaults.standard.persistentDomain(forName: oldDomain) {
            for key in [SettingsKey.menuBarMode, SettingsKey.lowDiskAlerts, SettingsKey.lowDiskThresholdGB]
            where defaults.object(forKey: key) == nil {
                if let value = old[key] { defaults.set(value, forKey: key) }
            }
        }
        defaults.set(true, forKey: doneKey)
    }
}
