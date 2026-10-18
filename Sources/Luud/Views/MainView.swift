import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var cleanup: CleanupModel
    @EnvironmentObject private var uninstaller: UninstallerModel
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var headerActive = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $router.selection) {
                ForEach(AppSection.allCases) { section in
                    Label {
                        Text(section.title)
                    } icon: {
                        Image(systemName: section.icon).foregroundStyle(section.tint)
                    }
                    .badge(badge(for: section))
                    .tag(section)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) {
                SidebarVitals(stats: stats).padding(12)
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .id(router.selection)
                .transition(.opacity)
                .onPreferenceChange(HeaderActivityKey.self) { headerActive = $0 }
                .background(alignment: .top) {
                    SectionBackdrop(section: router.selection ?? .smartCare, isActive: headerActive)
                }
        }
        // Transparent toolbar so the backdrop runs to the top edge; the sidebar toggle stays.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .animation(.easeInOut(duration: 0.2), value: router.selection)
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func badge(for section: AppSection) -> Text? {
        switch section {
        case .dashboard: Text(Fmt.percent(stats.cpu)).monospacedDigit()
        case .cleanup where cleanup.hasScanned && cleanup.totalSize > 0: Text(Fmt.bytes(cleanup.totalSize))
        case .uninstaller where uninstaller.hasLoaded && !uninstaller.unusedApps.isEmpty: Text("\(uninstaller.unusedApps.count)")
        default: nil
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.selection ?? .smartCare {
        case .smartCare: SmartCareView()
        case .dashboard: DashboardView()
        case .cleanup: CleanupView()
        case .uninstaller: UninstallerView()
        case .spaceLens: SpaceLensView()
        case .largeFiles: LargeFilesView()
        case .performance: PerformanceView()
        case .settings: SettingsView()
        }
    }
}

private struct SidebarVitals: View {
    @ObservedObject var stats: SystemStats

    var body: some View {
        HStack(spacing: 10) {
            VitalsRings(rings: [
                .init(id: "cpu", value: stats.cpu, color: Palette.cpu),
                .init(id: "memory", value: stats.memoryFraction, color: Palette.memory),
                .init(id: "disk", value: stats.diskUsedFraction, color: Palette.disk),
            ], lineWidth: 5, gap: 2)
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Macintosh HD").font(.caption.weight(.semibold))
                Text("\(Fmt.bytes(stats.diskFree)) free").font(.caption2).foregroundStyle(.secondary)
                Text("\(Fmt.percent(stats.cpu)) CPU · \(Fmt.percent(stats.memoryFraction)) memory")
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
    }
}

// MARK: - Smart Care

struct SmartCareView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var cleanup: CleanupModel
    @EnvironmentObject private var uninstaller: UninstallerModel
    @State private var isScanning = false
    @State private var confirmClean = false

    private var busy: Bool { isScanning || cleanup.isCleaning }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                PageHeader(section: .smartCare, subtitle: headline, isActive: busy) { EmptyView() }

                ScanOrb(isBusy: busy, title: orbTitle, detail: orbDetail, value: Double(cleanup.selectedSize)) {
                    if cleanup.hasScanned && cleanup.selectedSize > 0 {
                        confirmClean = true
                    } else {
                        scan()
                    }
                }

                if cleanup.hasScanned || uninstaller.hasLoaded {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            Finding(icon: "trash", tint: Palette.network, title: "Junk",
                                    value: Fmt.bytes(cleanup.selectedSize), numeric: Double(cleanup.selectedSize),
                                    detail: "selected of \(Fmt.bytes(cleanup.totalSize)) found", action: "Review") {
                                router.selection = .cleanup
                            }
                            Finding(icon: "xmark.app", tint: Palette.disk, title: "Unused apps",
                                    value: "\(uninstaller.unusedApps.count)", numeric: Double(uninstaller.unusedApps.count),
                                    detail: "not opened in six months", action: "Review") {
                                router.selection = .uninstaller
                            }
                        }
                        HStack(spacing: 14) {
                            Finding(icon: "internaldrive", tint: stats.diskUsedFraction > 0.9 ? Palette.danger : Palette.memory,
                                    title: "Startup disk", value: "\(Fmt.bytes(stats.diskFree)) free", numeric: Double(stats.diskFree),
                                    detail: stats.diskUsedFraction > 0.9 ? "Running low. See what's big in Space Lens." : "\(Fmt.percent(stats.diskUsedFraction)) used",
                                    action: "Space Lens") {
                                router.selection = .spaceLens
                            }
                            Finding(icon: "memorychip", tint: Palette.cpu, title: "Memory",
                                    value: Fmt.percent(stats.memoryFraction), numeric: stats.memoryFraction,
                                    detail: stats.topMemory.first.map { "\($0.name) uses the most (\(Fmt.bytes($0.memory)))" } ?? "",
                                    action: "Dashboard") {
                                router.selection = .dashboard
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                    if cleanup.needsFullDiskAccess { FullDiskAccessHint() }
                }
            }
            .padding(.bottom, 28)
            .animation(.spring(response: 0.6, dampingFraction: 0.85), value: cleanup.hasScanned || uninstaller.hasLoaded)
        }
        .confirmationDialog("Clean \(Fmt.bytes(cleanup.selectedSize)) of junk?", isPresented: $confirmClean) {
            Button("Clean", role: .destructive) { Task { await cleanup.clean() } }
            Button("Review First") { router.selection = .cleanup }
        } message: {
            Text("Caches and logs are deleted (apps rebuild them); installers and Mail attachments go to the Trash.")
        }
    }

    private var headline: String {
        if isScanning { return "Checking junk, apps and disk…" }
        if cleanup.isCleaning { return "Cleaning…" }
        if let result = cleanup.lastResult { return resultText(result) }
        if cleanup.hasScanned { return "Here's what Luud found" }
        return "One scan for junk, unused apps and disk space"
    }

    private var orbTitle: String {
        if cleanup.hasScanned && cleanup.selectedSize > 0 { return Fmt.bytes(cleanup.selectedSize) }
        return cleanup.hasScanned ? "Scan again" : "Scan"
    }

    private var orbDetail: String? {
        if busy { return nil }
        if cleanup.hasScanned && cleanup.selectedSize > 0 { return "Click to clean" }
        return nil
    }

    private func scan() {
        isScanning = true
        Task {
            async let junk: Void = cleanup.scan()
            async let apps: Void = uninstaller.load()
            _ = await (junk, apps)
            isScanning = false
        }
    }

    private func resultText(_ result: CleanupResult) -> String {
        var parts = ["Cleaned \(Fmt.bytes(result.deleted))"]
        if result.trashed > 0 { parts.append("moved \(Fmt.bytes(result.trashed)) to the Trash") }
        if !result.failures.isEmpty { parts.append("skipped \(result.failures.count) items in use") }
        return parts.joined(separator: ", ")
    }
}

/// The hero control: a living gradient orb that speeds up and shows a sweep while working.
private struct ScanOrb: View {
    let isBusy: Bool
    let title: String
    let detail: String?
    let value: Double
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // The glow is a separate still layer, so the moving gradient never forces a re-blur.
                Circle()
                    .fill(Palette.brandGradient)
                    .blur(radius: isHovering ? 34 : 24)
                    .opacity(isHovering ? 0.6 : 0.4)
                LiveBackdrop(colors: [Palette.brandPink, Palette.brandViolet, .orange], speed: isBusy ? 2.2 : 0.6)
                    .clipShape(Circle())
                    .overlay(Circle().fill(.white.opacity(0.08)))
                if isBusy {
                    SweepRing(color: .white, lineWidth: 5).padding(10)
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    VStack(spacing: 4) {
                        LiveValue(text: title, value: value, size: 30, weight: .heavy)
                        if let detail { Text(detail).font(.callout.weight(.medium)).opacity(0.85) }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                }
            }
            .frame(width: 190, height: 190)
            .scaleEffect(isHovering && !isBusy ? 1.03 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { isHovering = $0 }
    }
}

private struct Finding: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String
    let numeric: Double
    let detail: String
    let action: String
    let onAction: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.15), in: RoundedRectangle(
                        cornerRadius: Corner.inner(Corner.panel, padding: Corner.panelPadding), style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    LiveValue(text: value, value: numeric, size: 26, weight: .heavy)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button(action, action: onAction)
                    .buttonBorderShape(.roundedRectangle(radius: Corner.inner(Corner.panel, padding: Corner.panelPadding)))
            }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    enum ProcessSort: String, CaseIterable, Identifiable {
        case cpu = "CPU", memory = "Memory"
        var id: String { rawValue }
    }

    @EnvironmentObject private var stats: SystemStats
    @State private var processSort: ProcessSort = .cpu

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageHeader(section: .dashboard, subtitle: "\(MachineInfo.chip), \(MachineInfo.osVersion), up \(Fmt.duration(stats.uptime))") {
                    EmptyView()
                }

                vitals.padding(.horizontal, 28)

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                MetricHeader(title: "CPU", icon: "cpu", tint: Palette.cpu)
                                Spacer()
                                Text("\(MachineInfo.coreCount) cores, last minute").font(.caption).foregroundStyle(.tertiary)
                            }
                            HistoryChart(series: [.init(id: "CPU", values: stats.cpuHistory, color: Palette.cpu)],
                                         maxValue: 1, label: Fmt.percent)
                                .frame(height: 130)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline) {
                                MetricHeader(title: "Network", icon: "arrow.up.arrow.down", tint: Palette.network)
                                Spacer()
                                LiveValue(text: "↓ \(Fmt.rate(stats.networkIn))", value: stats.networkIn, size: 13, weight: .semibold)
                                    .foregroundStyle(Palette.network)
                                LiveValue(text: "↑ \(Fmt.rate(stats.networkOut))", value: stats.networkOut, size: 13, weight: .semibold)
                                    .foregroundStyle(Palette.upload)
                            }
                            HistoryChart(series: [
                                .init(id: "Download", values: stats.networkInHistory, color: Palette.network),
                                .init(id: "Upload", values: stats.networkOutHistory, color: Palette.upload),
                            ], label: { Fmt.rate($0) })
                            .frame(height: 130)
                        }
                    }
                }
                .padding(.horizontal, 28)

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            MetricHeader(title: "Memory", icon: "memorychip", tint: Palette.memory)
                            MemoryBreakdown(memory: stats.memory, total: stats.memoryTotal)
                            HistoryChart(series: [.init(id: "Memory", values: stats.memoryHistory, color: Palette.memory)],
                                         maxValue: 1, label: Fmt.percent)
                                .frame(height: 70)
                        }
                    }
                    if let battery = stats.battery {
                        Card {
                            VStack(alignment: .leading, spacing: 12) {
                                MetricHeader(title: "Battery", icon: "battery.75percent", tint: Palette.network)
                                HStack(alignment: .firstTextBaseline) {
                                    LiveValue(text: Fmt.percent(battery.level), value: battery.level, size: 34, weight: .heavy)
                                    Spacer()
                                }
                                UsageBar(fraction: battery.level, tint: battery.level < 0.2 ? Palette.danger : Palette.network, height: 10)
                                BatteryStrip(battery: battery).foregroundStyle(.secondary)
                                if let temperature = battery.temperature {
                                    Text("Temperature \(String(format: "%.1f", temperature)) °C")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .frame(maxWidth: 340)
                    }
                }
                .padding(.horizontal, 28)

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            MetricHeader(title: "Processes", icon: "list.bullet.rectangle", tint: .primary)
                            Spacer()
                            Picker("", selection: $processSort) {
                                ForEach(ProcessSort.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 170)
                        }
                        let processes = processSort == .cpu ? stats.topCPU : stats.topMemory
                        let topMemory = Double(stats.topMemory.first?.memory ?? 1)
                        ForEach(processes) { process in
                            ProcessRow(
                                process: process,
                                metric: processSort == .cpu ? Fmt.percent(process.cpu) : Fmt.bytes(process.memory),
                                share: processSort == .cpu
                                    ? min(process.cpu, 1)
                                    : Double(process.memory) / max(topMemory, 1),
                                tint: processSort == .cpu ? Palette.cpu : Palette.memory
                            )
                            .padding(.vertical, 2)
                        }
                        Text("Shows your own processes. System processes owned by root need admin rights to inspect.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .animation(.snappy, value: processes(for: processSort).map(\.id))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
    }

    private func processes(for sort: ProcessSort) -> [ProcessSample] {
        sort == .cpu ? stats.topCPU : stats.topMemory
    }

    /// The signature element: concentric live rings with large rolling numbers beside them.
    private var vitals: some View {
        HStack(spacing: 36) {
            VitalsRings(rings: [
                .init(id: "cpu", value: stats.cpu, color: Palette.cpu),
                .init(id: "memory", value: stats.memoryFraction, color: Palette.memory),
                .init(id: "disk", value: stats.diskUsedFraction, color: Palette.disk),
            ], lineWidth: 18, gap: 5)
            .frame(width: 190, height: 190)

            VStack(alignment: .leading, spacing: 18) {
                VitalLine(color: Palette.cpu, title: "CPU", value: Fmt.percent(stats.cpu), numeric: stats.cpu,
                          detail: stats.topCPU.first.map { "\($0.name) is busiest" } ?? "")
                VitalLine(color: Palette.memory, title: "Memory", value: Fmt.percent(stats.memoryFraction), numeric: stats.memoryFraction,
                          detail: "\(Fmt.bytes(stats.memoryUsed)) of \(Fmt.bytes(stats.memoryTotal)) in use")
                VitalLine(color: Palette.disk, title: "Disk", value: Fmt.percent(stats.diskUsedFraction), numeric: stats.diskUsedFraction,
                          detail: "\(Fmt.bytes(stats.diskFree)) free of \(Fmt.bytes(stats.diskTotal))")
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct VitalLine: View {
    let color: Color
    let title: String
    let value: String
    let numeric: Double
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            LiveValue(text: value, value: numeric, size: 40, weight: .heavy)
                .foregroundStyle(color)
                .frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct MemoryBreakdown: View {
    let memory: MemorySnapshot
    let total: UInt64

    var body: some View {
        let parts: [(String, UInt64, Color)] = [
            ("App", memory.app, Palette.memory),
            ("Wired", memory.wired, Palette.disk),
            ("Compressed", memory.compressed, Palette.brandPink),
            ("Cached", memory.cached, .gray),
        ]
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle()
                            .fill(part.2.gradient)
                            .frame(width: max(0, proxy.size.width * min(1, CGFloat(Double(part.1) / Double(max(total, 1)))) - 2))
                    }
                    Spacer(minLength: 0)
                }
                .animation(Motion.live, value: memory.used)
            }
            .frame(height: 14)
            .background(.fill.tertiary)
            .clipShape(Capsule())
            HStack(spacing: 14) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 5) {
                        Circle().fill(part.2).frame(width: 7, height: 7)
                        Text(part.0).foregroundStyle(.secondary)
                        Text(Fmt.bytes(part.1)).monospacedDigit()
                    }
                }
                if memory.swapUsed > 0 {
                    Text("Swap \(Fmt.bytes(memory.swapUsed))").foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}
