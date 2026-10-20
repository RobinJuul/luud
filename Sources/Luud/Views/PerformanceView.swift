import ServiceManagement
import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject private var model: PerformanceModel
    @State private var pendingRemoval: LaunchItem?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .performance, subtitle: "Maintenance tasks and background items", isActive: model.runningTask != nil) {
                Button("Login Items…") { SystemSettings.openLoginItems() }.controlSize(.large)
            }

            if let message = model.message {
                StatusBanner(text: message, isError: message.contains("failed") || message.contains("Couldn't")) {
                    model.message = nil
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Maintenance").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(MaintenanceTask.allCases) { task in
                            Card(padding: 14, radius: 14 + 6) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label(task.title, systemImage: task.icon).font(.headline)
                                        Spacer()
                                        if task.needsAdmin {
                                            Image(systemName: "lock").foregroundStyle(.secondary).help("Asks for your password")
                                        }
                                    }
                                    Text(task.detail).font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    HStack {
                                        Spacer()
                                        if model.runningTask == task { ProgressView().controlSize(.small) }
                                        Button("Run") { Task { await model.run(task) } }
                                            .disabled(model.runningTask != nil)
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Text("Background items").font(.title3.bold())
                        if model.isLoading { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Refresh") { Task { await model.load() } }
                    }
                    Text("Launch agents and daemons start helpers in the background. Disabling is reversible; system daemons ask for your password.")
                        .font(.callout).foregroundStyle(.secondary)

                    ForEach(LaunchItem.Scope.allCases, id: \.self) { scope in
                        let items = model.items.filter { $0.scope == scope }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(scope.rawValue).font(.headline).padding(.bottom, 6)
                                ForEach(items) { item in
                                    LaunchItemRow(item: item, isBusy: model.busyItem == item.id,
                                                  onToggle: { disabled in Task { await model.setDisabled(item, disabled: disabled) } },
                                                  onRemove: { pendingRemoval = item })
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .task { if model.items.isEmpty { await model.load() } }
        .confirmationDialog("Remove \(pendingRemoval?.label ?? "")?",
                            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let item = pendingRemoval { Task { await model.remove(item) } }
            }
        } message: {
            Text("The agent is stopped and its plist moved to the Trash.")
        }
    }
}

private struct LaunchItemRow: View {
    let item: LaunchItem
    let isBusy: Bool
    let onToggle: (Bool) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label).fontWeight(.medium).foregroundStyle(item.isDisabled ? .secondary : .primary)
                if let program = item.program {
                    Text(program).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if item.keepsAlive { Tag(text: "Always running") }
            if item.runsAtLoad { Tag(text: "Starts at login") }
            if isBusy { ProgressView().controlSize(.small) }
            Toggle("", isOn: Binding(get: { !item.isDisabled }, set: { onToggle(!$0) }))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isBusy)
            Menu {
                Button("Show in Finder") { item.url.revealInFinder() }
                if item.scope == .userAgent {
                    Button("Remove…", role: .destructive, action: onRemove)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 8)
    }
}

private struct Tag: View {
    let text: String
    var body: some View {
        Text(text).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage(SettingsKey.menuBarMode) private var menuBarMode = MenuBarMode.cpuAndMemory.rawValue
    @AppStorage(SettingsKey.lowDiskAlerts) private var lowDiskAlerts = true
    @AppStorage(SettingsKey.lowDiskThresholdGB) private var lowDiskThresholdGB = 15
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .settings, subtitle: "Menu bar, alerts and permissions") { EmptyView() }
            Form {
                SwiftUI.Section("General") {
                    Toggle("Open at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.orange)
                    }
                    Picker("Menu bar shows", selection: $menuBarMode) {
                        ForEach(MenuBarMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                }
                SwiftUI.Section("Alerts") {
                    Toggle("Notify me when the startup disk is almost full", isOn: $lowDiskAlerts)
                    Stepper("Alert below \(lowDiskThresholdGB) GB free", value: $lowDiskThresholdGB, in: 5...100, step: 5)
                        .disabled(!lowDiskAlerts)
                }
                SwiftUI.Section("Apple Intelligence") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(aiStatus, systemImage: aiReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundStyle(aiReady ? Palette.network : .orange)
                            Text("Used by the Explain button to describe files and folders. It runs on your Mac; nothing is sent anywhere.")
                                .font(.caption).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if ItemExplainer.isCompiledIn && !aiReady {
                            Button("Open Settings") { SystemSettings.openAppleIntelligence() }
                        }
                    }
                    if ItemExplainer.canBeTurnedOn {
                        Text("In System Settings, open Apple Intelligence & Siri and turn on Apple Intelligence. It downloads its model the first time, which needs several gigabytes of free space and can take a while. Your Mac's language and Siri's language need to be the same supported language.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SwiftUI.Section("Permissions") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Full Disk Access")
                            Text("Needed to scan the Trash, Mail attachments and some app data.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open Settings") { SystemSettings.openFullDiskAccess() }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: 640)
        }
    }

    private var aiReady: Bool { ItemExplainer.unavailableReason == nil }
    private var aiStatus: String { ItemExplainer.unavailableReason ?? "Ready on this Mac" }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
