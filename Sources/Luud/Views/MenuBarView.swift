import AppKit
import SwiftUI

enum MenuBarMode: String, CaseIterable, Identifiable {
    case cpuAndMemory, cpu, memory, network, icon

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpuAndMemory: "CPU and memory"
        case .cpu: "CPU"
        case .memory: "Memory"
        case .network: "Network speed"
        case .icon: "Icon only"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var stats: SystemStats
    let router: Router
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.menuBarMode) private var mode = MenuBarMode.cpuAndMemory.rawValue

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Glyph.menuBar)
            switch MenuBarMode(rawValue: mode) ?? .cpuAndMemory {
            case .cpuAndMemory: Text("\(Fmt.percent(stats.cpu))  \(Fmt.percent(stats.memoryFraction))")
            case .cpu: Text(Fmt.percent(stats.cpu))
            case .memory: Text(Fmt.percent(stats.memoryFraction))
            case .network: Text("↓\(Fmt.rate(stats.networkIn))")
            case .icon: EmptyView()
            }
        }
        .monospacedDigit()
        .onAppear {
            router.openWindowAction = openWindow
            if LaunchOptions.menuPreview { openWindow(id: Router.menuPreviewWindowID) }
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var stats: SystemStats
    @EnvironmentObject private var router: Router
    @State private var isFreeingRAM = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 10) {
                GaugeRow(icon: "cpu", title: "CPU", tint: Palette.cpu,
                         value: Fmt.percent(stats.cpu), numeric: stats.cpu) {
                    Sparkline(values: stats.cpuHistory, tint: Palette.cpu)
                }
                GaugeRow(icon: "memorychip", title: "Memory", tint: Palette.memory,
                         value: Fmt.bytes(stats.memoryUsed), numeric: Double(stats.memoryUsed)) {
                    Sparkline(values: stats.memoryHistory, tint: Palette.memory)
                }
                GaugeRow(icon: "arrow.down.circle", title: "Download", tint: Palette.network,
                         value: Fmt.rate(stats.networkIn), numeric: stats.networkIn) {
                    Sparkline(values: stats.networkInHistory, tint: Palette.network,
                              maxValue: max(stats.networkInHistory.max() ?? 1, 64_000))
                }
                GaugeRow(icon: "arrow.up.circle", title: "Upload", tint: Palette.upload,
                         value: Fmt.rate(stats.networkOut), numeric: stats.networkOut) {
                    Sparkline(values: stats.networkOutHistory, tint: Palette.upload,
                              maxValue: max(stats.networkOutHistory.max() ?? 1, 64_000))
                }
                GaugeRow(icon: "internaldrive", title: "Disk", tint: Palette.disk,
                         value: "\(Fmt.bytes(stats.diskFree)) free", numeric: Double(stats.diskFree)) {
                    UsageBar(fraction: stats.diskUsedFraction, tint: Palette.disk, height: 6)
                }
                if let battery = stats.battery {
                    GaugeRow(icon: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                             title: "Battery", tint: battery.level < 0.2 ? Palette.danger : Palette.network,
                             value: Fmt.percent(battery.level), numeric: battery.level) {
                        UsageBar(fraction: battery.level, tint: battery.level < 0.2 ? Palette.danger : Palette.network, height: 6)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Busiest right now").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(stats.topCPU.prefix(4)) { process in
                    ProcessRow(process: process, metric: Fmt.percent(process.cpu),
                               share: min(process.cpu / Double(max(MachineInfo.coreCount, 1)) * 4, 1), tint: Palette.cpu)
                }
            }

            HStack(spacing: 8) {
                Button(action: freeRAM) {
                    Label(isFreeingRAM ? "Freeing…" : "Free up RAM", systemImage: "memorychip")
                        .frame(maxWidth: .infinity)
                }
                .disabled(isFreeingRAM)
                Button { router.openMain(.cleanup) } label: {
                    Label("Clean junk", systemImage: "sparkles").frame(maxWidth: .infinity)
                }
                .tint(Palette.brandPink)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)

            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary).transition(.opacity)
            }

            HStack {
                Button("Open Luud") { router.openMain() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(16)
        .frame(width: 340)
        .background(alignment: .top) {
            LiveBackdrop(colors: [Palette.cpu, Palette.memory, Palette.brandPink], speed: 0.3)
                .frame(height: 150)
                .opacity(0.35)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VitalsRings(rings: [
                .init(id: "cpu", value: stats.cpu, color: Palette.cpu),
                .init(id: "memory", value: stats.memoryFraction, color: Palette.memory),
                .init(id: "disk", value: stats.diskUsedFraction, color: Palette.disk),
            ], lineWidth: 7, gap: 2.5)
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Luud").font(.system(.headline, design: .rounded))
                    Spacer()
                    Text("up \(Fmt.duration(stats.uptime))").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    RingLegend(color: Palette.cpu, label: "CPU", value: stats.cpu)
                    RingLegend(color: Palette.memory, label: "Memory", value: stats.memoryFraction)
                    RingLegend(color: Palette.disk, label: "Disk", value: stats.diskUsedFraction)
                }
            }
        }
    }

    private func freeRAM() {
        isFreeingRAM = true
        let before = stats.memoryUsed
        Task {
            let result = await Task.detached { Shell.runAsAdmin(MaintenanceTask.freeRAM.command) }.value
            if result.succeeded {
                try? await Task.sleep(for: .seconds(2))
                let freed = Int64(before) - Int64(stats.memoryUsed)
                withAnimation { status = freed > 0 ? "Freed \(Fmt.bytes(freed)) of memory." : "Memory purged." }
            } else {
                withAnimation { status = result.wasCancelled ? nil : "Couldn't free memory." }
            }
            isFreeingRAM = false
        }
    }
}

private struct RingLegend: View {
    let color: Color
    let label: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LiveValue(text: Fmt.percent(value), value: value, size: 17)
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct GaugeRow<Graph: View>: View {
    let icon: String
    let title: String
    let tint: Color
    let value: String
    let numeric: Double
    @ViewBuilder let graph: Graph

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title).font(.callout).frame(width: 66, alignment: .leading)
            graph.frame(height: 20)
            LiveValue(text: value, value: numeric, size: 13, weight: .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 96, alignment: .trailing)
        }
    }
}

struct BatteryStrip: View {
    let battery: BatteryInfo

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(battery.level < 0.2 ? Palette.danger : Palette.network)
            Text(Fmt.percent(battery.level)).monospacedDigit().fontWeight(.semibold)
            Text(state).foregroundStyle(.secondary)
            Spacer()
            if let health = battery.health {
                Text("Health \(Fmt.percent(health))").foregroundStyle(.secondary)
            }
            if let cycles = battery.cycleCount {
                Text("\(cycles) cycles").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var symbol: String {
        if battery.isCharging { return "battery.100percent.bolt" }
        switch battery.level {
        case ..<0.13: return "battery.0percent"
        case ..<0.38: return "battery.25percent"
        case ..<0.63: return "battery.50percent"
        case ..<0.88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var state: String {
        if battery.isCharging { return "Charging" }
        if battery.onACPower { return "On power adapter" }
        if let minutes = battery.minutesRemaining { return "\(minutes / 60)h \(minutes % 60)m left" }
        return "On battery"
    }
}

struct ProcessRow: View {
    let process: ProcessSample
    let metric: String
    var share: Double?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 8) {
            if let icon = IconCache.appIcon(pid: process.id) {
                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
            } else {
                Image(systemName: "gearshape.fill").frame(width: 18, height: 18).foregroundStyle(.tertiary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(process.name).lineLimit(1)
                if let share {
                    UsageBar(fraction: share, tint: tint, height: 3)
                }
            }
            Spacer(minLength: 8)
            Text(metric).monospacedDigit().foregroundStyle(.secondary)
            if process.isApp {
                Button {
                    NSRunningApplication(processIdentifier: process.id)?.terminate()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Quit \(process.name)")
            }
        }
        .font(.callout)
        .transition(.opacity)
    }
}
