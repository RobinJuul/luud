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
                // Scroll views only sometimes apply the toolbar inset, so every screen opts out
                // and PageHeader adds a fixed top margin instead.
                .ignoresSafeArea(.container, edges: .top)
                .onPreferenceChange(HeaderActivityKey.self) { headerActive = $0 }
                .background(alignment: .top) {
                    SectionBackdrop(section: router.selection ?? .smartCare, isActive: headerActive)
                }
        }
        // Transparent toolbar so the backdrop runs to the top edge; the sidebar toggle stays.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .animation(.easeInOut(duration: 0.2), value: router.selection)
        // Narrower than this, the Dashboard's two columns get crushed.
        .frame(minWidth: 1060, minHeight: 640)
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
    @AppStorage("smartCareHasScanned") private var hasEverScanned = false

    private var busy: Bool { isScanning || cleanup.isCleaning }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .smartCare, subtitle: headline, isActive: busy) { EmptyView() }
            // The page doesn't scroll: roomy when it fits, compact on smaller windows,
            // scrolling only if even that doesn't fit.
            FittingLayout { compact in content(compact: compact) }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: cleanup.hasScanned || uninstaller.hasLoaded)
        .task {
            if LaunchOptions.autoScan && LaunchOptions.section == .smartCare && !cleanup.hasScanned { scan() }
        }
        .confirmationDialog("Clean \(Fmt.bytes(cleanup.selectedSize)) of junk?", isPresented: $confirmClean) {
            Button("Clean", role: .destructive) { Task { await cleanup.clean() } }
            Button("Review First") { router.selection = .cleanup }
        } message: {
            Text("Caches and logs are deleted (apps rebuild them); installers and Mail attachments go to the Trash.")
        }
    }

    private func content(compact: Bool) -> some View {
        let orb: CGFloat = compact ? 140 : 180
        return VStack(spacing: compact ? 12 : 18) {
            // The note sits to the left of the orb; an equal spacer on the right keeps the orb centred.
            HStack(spacing: 12) {
                StartHereNote(isVisible: showStartHere)
                    .frame(width: 230, height: orb)
                ScanOrb(isBusy: busy, title: orbTitle, detail: orbDetail, value: Double(cleanup.selectedSize), size: orb) {
                    if cleanup.hasScanned && cleanup.selectedSize > 0 {
                        confirmClean = true
                    } else {
                        scan()
                    }
                }
                Color.clear.frame(width: 230, height: orb)
            }

            Text("Takes a few seconds. Nothing is removed until you review it.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Same four cards before and after a scan, so results land where the previews were.
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    Finding(icon: "trash", tint: Palette.network, title: "Junk",
                            value: cleanup.hasScanned ? Fmt.bytes(cleanup.selectedSize) : nil,
                            numeric: Double(cleanup.selectedSize),
                            detail: cleanup.hasScanned
                                ? "selected of \(Fmt.bytes(cleanup.totalSize)) found"
                                : "Caches, logs, Xcode and developer leftovers, old installers",
                            isChecking: cleanup.isScanning, compact: compact,
                            action: cleanup.hasScanned ? "Review" : nil) {
                        router.selection = .cleanup
                    }
                    Finding(icon: "xmark.app", tint: Palette.disk, title: "Unused apps",
                            value: uninstaller.hasLoaded ? "\(uninstaller.unusedApps.count)" : nil,
                            numeric: Double(uninstaller.unusedApps.count),
                            detail: uninstaller.hasLoaded
                                ? "not opened in six months"
                                : "Apps you haven't opened in six months, and what they leave behind",
                            isChecking: uninstaller.isLoading, compact: compact,
                            action: uninstaller.hasLoaded ? "Review" : nil) {
                        router.selection = .uninstaller
                    }
                }
                GridRow {
                    Finding(icon: "internaldrive", tint: stats.diskUsedFraction > 0.9 ? Palette.danger : Palette.memory,
                            title: "Startup disk", value: "\(Fmt.bytes(stats.diskFree)) free", numeric: Double(stats.diskFree),
                            detail: stats.diskUsedFraction > 0.9 ? "Running low. See what's big in Space Lens." : "\(Fmt.percent(stats.diskUsedFraction)) used",
                            compact: compact, action: "Space Lens") {
                        router.selection = .spaceLens
                    }
                    Finding(icon: "memorychip", tint: Palette.cpu, title: "Memory",
                            value: Fmt.percent(stats.memoryFraction), numeric: stats.memoryFraction,
                            detail: stats.topMemory.first.map { "\($0.name) uses the most (\(Fmt.bytes($0.memory)))" } ?? "",
                            compact: compact, action: "Dashboard") {
                        router.selection = .dashboard
                    }
                }
            }
            .padding(.horizontal, 28)

            if cleanup.needsFullDiskAccess { FullDiskAccessHint() }

            if let last = cleanup.lastCleaned {
                Text("Last cleaned \(Fmt.relativeDate(last.date)) · freed \(Fmt.bytes(last.bytes))")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.bottom, 20)
    }

    /// The hand-drawn hint shows until the first scan ever, then never again.
    private var showStartHere: Bool { !hasEverScanned && !cleanup.hasScanned && !busy }

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
            hasEverScanned = true
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
    var size: CGFloat = 190
    let action: () -> Void
    @State private var isHovering = false
    @FocusState private var isFocused: Bool

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
                        LiveValue(text: title, value: value, size: size > 160 ? 30 : 24, weight: .heavy)
                        if let detail { Text(detail).font(.callout.weight(.medium)).opacity(0.85) }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(isHovering && !isBusy ? 1.03 : 1)
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isHovering)
        }
        .buttonStyle(.plain)
        // The system focus ring is a square; draw a round one that follows the orb instead.
        .focusEffectDisabled()
        .focused($isFocused)
        .overlay {
            if isFocused {
                Circle().strokeBorder(Color.accentColor, lineWidth: 3).padding(-7).allowsHitTesting(false)
            }
        }
        .disabled(isBusy)
        .onHover { isHovering = $0 }
    }
}

/// One result card. Without a value it's a preview of what the scan will check.
private struct Finding: View {
    let icon: String
    let tint: Color
    let title: String
    let value: String?
    let numeric: Double
    let detail: String
    var isChecking = false
    var compact = false
    let action: String?
    let onAction: () -> Void

    private var isPreview: Bool { value == nil }

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
                    if let value {
                        LiveValue(text: value, value: numeric, size: compact ? 22 : 26, weight: .heavy)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else if isChecking {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Checking…").font(.system(size: 20, weight: .semibold, design: .rounded))
                        }
                        .frame(height: compact ? 26 : 32)
                    }
                    Text(detail)
                        .font(isPreview && !compact ? .body : .callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact && !isPreview ? 1 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let action {
                    Button(action, action: onAction)
                        .buttonBorderShape(.roundedRectangle(radius: Corner.inner(Corner.panel, padding: Corner.panelPadding)))
                }
            }
            .frame(minHeight: compact ? 60 : 84, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        // A dashed outline marks a card that's waiting for the scan.
        .overlay {
            if isPreview {
                RoundedRectangle(cornerRadius: Corner.panel, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 5]))
                    .foregroundStyle(.white.opacity(0.14))
            }
        }
        .animation(.easeOut(duration: 0.3), value: isPreview)
    }
}

/// "start here" in brush lettering with a painted arrow curving into the Scan orb.
/// Draws itself in once; shown only before the first scan.
private struct StartHereNote: View {
    let isVisible: Bool
    @State private var drawn: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let ink = LinearGradient(colors: [Palette.disk, Palette.brandPink], startPoint: .leading, endPoint: .trailing)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("start here!")
                .font(.custom("BradleyHandITCTT-Bold", size: 30))
                .foregroundStyle(ink)
                .rotationEffect(.degrees(-7))
                .offset(x: 18, y: 26)
                .opacity(drawn > 0 ? 1 : 0)
            // Two strokes, slightly apart, read as one dry brush mark.
            PaintedArrow()
                .trim(from: 0, to: drawn)
                .stroke(ink, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            PaintedArrow(jitter: 1.6)
                .trim(from: 0, to: drawn)
                .stroke(ink.opacity(0.45), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: isVisible)
        .accessibilityHidden(true)
        .onAppear {
            guard isVisible, drawn == 0 else { return }
            if reduceMotion {
                drawn = 1
            } else {
                withAnimation(.easeInOut(duration: 1.1).delay(0.5)) { drawn = 1 }
            }
        }
    }
}

/// A loose curve from under the note into the orb's left edge, ending in an open arrowhead.
private struct PaintedArrow: Shape {
    var jitter: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let start = CGPoint(x: w * 0.30 + jitter, y: h * 0.48)
        let end = CGPoint(x: w - 6, y: h * 0.58 + jitter * 0.5)
        let c1 = CGPoint(x: w * 0.22, y: h * 0.82 + jitter)
        let c2 = CGPoint(x: w * 0.70, y: h * 0.86 - jitter)

        var path = Path()
        path.move(to: start)
        path.addCurve(to: end, control1: c1, control2: c2)

        // Open arrowhead, angled along the curve's final direction.
        let angle = atan2(end.y - c2.y, end.x - c2.x)
        let length: CGFloat = 18
        for spread in [CGFloat.pi * 0.8, -CGFloat.pi * 0.78] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + length * cos(angle + spread),
                                     y: end.y + length * sin(angle + spread)))
        }
        return path
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
        VStack(spacing: 0) {
            PageHeader(section: .dashboard, subtitle: "\(MachineInfo.chip), \(MachineInfo.osVersion), up \(Fmt.duration(stats.uptime))") {
                EmptyView()
            }
            // Two columns that fit the window; compact on smaller windows, scrolling only as a last resort.
            FittingLayout { compact in columns(compact: compact) }
        }
    }

    private func columns(compact: Bool) -> some View {
        let gap: CGFloat = compact ? 12 : 16
        let chartHeight: CGFloat = compact ? 70 : 100
        return HStack(alignment: .top, spacing: gap) {
            VStack(spacing: gap) {
                vitals(compact: compact)

                HStack(alignment: .top, spacing: gap) {
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            MetricHeader(title: "CPU", icon: "cpu", tint: Palette.cpu)
                            Text("\(MachineInfo.coreCount) cores, last minute")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary).lineLimit(1)
                            HistoryChart(series: [.init(id: "CPU", values: stats.cpuHistory, color: Palette.cpu)],
                                         maxValue: 1, label: Fmt.percent)
                                .frame(height: chartHeight)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            MetricHeader(title: "Network", icon: "arrow.up.arrow.down", tint: Palette.network)
                            HStack(spacing: 12) {
                                LiveValue(text: "↓ \(Fmt.rate(stats.networkIn))", value: stats.networkIn, size: 13, weight: .semibold)
                                    .foregroundStyle(Palette.network)
                                LiveValue(text: "↑ \(Fmt.rate(stats.networkOut))", value: stats.networkOut, size: 13, weight: .semibold)
                                    .foregroundStyle(Palette.upload)
                            }
                            .lineLimit(1)
                            HistoryChart(series: [
                                .init(id: "Download", values: stats.networkInHistory, color: Palette.network),
                                .init(id: "Upload", values: stats.networkOutHistory, color: Palette.upload),
                            ], label: { Fmt.rate($0) })
                            .frame(height: chartHeight)
                        }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            MetricHeader(title: "Memory", icon: "memorychip", tint: Palette.memory)
                            Spacer()
                            Text("\(Fmt.bytes(stats.memoryUsed)) of \(Fmt.bytes(stats.memoryTotal))")
                                .font(.callout.weight(.semibold)).monospacedDigit()
                        }
                        MemoryBreakdown(memory: stats.memory, total: stats.memoryTotal)
                    }
                }
            }

            VStack(spacing: gap) {
                processes(rows: compact ? 5 : 7)
                if let battery = stats.battery { batteryCard(battery) }
            }
            .frame(width: 300)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    /// Concentric live rings with large rolling numbers beside them.
    private func vitals(compact: Bool) -> some View {
        HStack(spacing: compact ? 22 : 30) {
            VitalsRings(rings: [
                .init(id: "cpu", value: stats.cpu, color: Palette.cpu),
                .init(id: "memory", value: stats.memoryFraction, color: Palette.memory),
                .init(id: "disk", value: stats.diskUsedFraction, color: Palette.disk),
            ], lineWidth: compact ? 12 : 15, gap: 4)
            .frame(width: compact ? 120 : 150, height: compact ? 120 : 150)

            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                VitalLine(color: Palette.cpu, title: "CPU", value: Fmt.percent(stats.cpu), numeric: stats.cpu,
                          detail: stats.topCPU.first.map { "\($0.name) is busiest" } ?? "", size: compact ? 28 : 34)
                VitalLine(color: Palette.memory, title: "Memory", value: Fmt.percent(stats.memoryFraction), numeric: stats.memoryFraction,
                          detail: "\(Fmt.bytes(stats.memoryUsed)) of \(Fmt.bytes(stats.memoryTotal)) in use", size: compact ? 28 : 34)
                VitalLine(color: Palette.disk, title: "Disk", value: Fmt.percent(stats.diskUsedFraction), numeric: stats.diskUsedFraction,
                          detail: "\(Fmt.bytes(stats.diskFree)) free of \(Fmt.bytes(stats.diskTotal))", size: compact ? 28 : 34)
            }
            Spacer(minLength: 0)
        }
    }

    private func processes(rows: Int) -> some View {
        let list = processSort == .cpu ? stats.topCPU : stats.topMemory
        let topMemory = Double(stats.topMemory.first?.memory ?? 1)
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MetricHeader(title: "Processes", icon: "list.bullet.rectangle", tint: .primary)
                    Spacer()
                    Picker("", selection: $processSort) {
                        ForEach(ProcessSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 140)
                }
                ForEach(list.prefix(rows)) { process in
                    ProcessRow(
                        process: process,
                        metric: processSort == .cpu ? Fmt.percent(process.cpu) : Fmt.bytes(process.memory),
                        share: processSort == .cpu ? min(process.cpu, 1) : Double(process.memory) / max(topMemory, 1),
                        tint: processSort == .cpu ? Palette.cpu : Palette.memory
                    )
                }
                Text("Your own processes; system ones need admin rights.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func batteryState(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return "Charging" }
        if battery.onACPower { return "On power adapter" }
        if let minutes = battery.minutesRemaining { return "\(minutes / 60)h \(minutes % 60)m left" }
        return "On battery"
    }

    private func batteryCard(_ battery: BatteryInfo) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    MetricHeader(title: "Battery", icon: "battery.75percent", tint: Palette.network)
                    Spacer()
                    LiveValue(text: Fmt.percent(battery.level), value: battery.level, size: 22, weight: .heavy)
                }
                UsageBar(fraction: battery.level, tint: battery.level < 0.2 ? Palette.danger : Palette.network, height: 8)
                HStack {
                    Text(batteryState(battery))
                    Spacer()
                    if let health = battery.health { Text("Health \(Fmt.percent(health))") }
                    if let cycles = battery.cycleCount { Text("\(cycles) cycles") }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VitalLine: View {
    let color: Color
    let title: String
    let value: String
    let numeric: Double
    let detail: String
    var size: CGFloat = 40

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            // Room for "100%"; shrinks slightly rather than wrapping.
            LiveValue(text: value, value: numeric, size: size, weight: .heavy)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(color)
                .frame(width: size * 3.1, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                }
                Text(title).font(.headline)
            }
        }
    }
}

private struct MemoryBreakdown: View {
    let memory: MemorySnapshot
    let total: UInt64

    private func legendItem(_ part: (String, UInt64, Color)) -> some View {
        HStack(spacing: 5) {
            Circle().fill(part.2).frame(width: 7, height: 7)
            Text(part.0).foregroundStyle(.secondary)
            Text(Fmt.bytes(part.1)).monospacedDigit()
        }
        .fixedSize()
    }

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

            }
            .frame(height: 14)
            .background(.fill.tertiary)
            .clipShape(Capsule())
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    ForEach(parts, id: \.0) { part in legendItem(part) }
                    if memory.swapUsed > 0 { Text("Swap \(Fmt.bytes(memory.swapUsed))").foregroundStyle(.secondary) }
                }
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                    GridRow { legendItem(parts[0]); legendItem(parts[1]) }
                    GridRow { legendItem(parts[2]); legendItem(parts[3]) }
                }
            }
            .font(.caption)
        }
    }
}
