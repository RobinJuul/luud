import AppKit
import Charts
import SwiftUI

struct Sparkline: View {
    let values: [Double]
    let tint: Color
    /// Fixed top of the scale (1 for fractions); nil scales to the data.
    var maxValue: Double? = 1

    var body: some View {
        let top = maxValue ?? max(values.max() ?? 1, 1)
        Chart(Array(values.enumerated()), id: \.offset) { item in
            AreaMark(x: .value("Time", item.offset), y: .value("Value", item.element))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.4), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("Time", item.offset), y: .value("Value", item.element))
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(SystemStats.historyLength - 1, 1))
        .chartYScale(domain: 0...top)
    }
}

/// Full chart for the dashboard: faint grid, trailing axis labels, optional second series.
struct HistoryChart: View {
    struct Series: Identifiable {
        let id: String
        let values: [Double]
        let color: Color
    }

    let series: [Series]
    var maxValue: Double?
    let label: (Double) -> String

    var body: some View {
        let top = maxValue ?? max(series.flatMap(\.values).max() ?? 1, 1) * 1.15
        Chart {
            ForEach(series) { s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { item in
                    AreaMark(x: .value("Time", item.offset), y: .value(s.id, item.element), series: .value("Series", s.id))
                        .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.32), s.color.opacity(0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", item.offset), y: .value(s.id, item.element), series: .value("Series", s.id))
                        .foregroundStyle(s.color)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartXScale(domain: 0...max(SystemStats.historyLength - 1, 1))
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])).foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(label(v)).font(.caption2).foregroundStyle(.tertiary) }
                }
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(max(fraction, 0), 1)))
                    .animation(Motion.live, value: fraction)
            }
        }
        .frame(height: height)
    }
}

/// Quiet container. Anything nested near its corners uses `Corner.inner(radius, padding:)`.
struct Card<Content: View>: View {
    var padding: CGFloat = Corner.panelPadding
    var radius: CGFloat = Corner.panel
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct MetricHeader: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
    }
}

/// Section hero: a live mesh backdrop in the section's colors that fades into the window.
struct PageHeader<Trailing: View>: View {
    let section: AppSection
    let subtitle: String
    var isActive = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: section.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.18), in: Circle())
                    .symbolEffect(.pulse, isActive: isActive)
                    .padding(.bottom, 6)
                Text(section.title)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: subtitle)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 28)
        .padding(.top, 72)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The backdrop itself lives behind the detail column (see MainView) so it can reach
        // under the transparent toolbar; the header only reports whether work is running.
        .preference(key: HeaderActivityKey.self, value: isActive)
    }
}

struct HeaderActivityKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

/// The section's mesh backdrop, pinned to the top of the window behind scrolling content.
struct SectionBackdrop: View {
    let section: AppSection
    let isActive: Bool

    var body: some View {
        LiveBackdrop(colors: section.backdrop, speed: isActive ? 1.6 : 0.35)
            .opacity(0.55)
            .frame(height: 300)
            .mask(LinearGradient(colors: [.black, .black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom))
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

struct StatusBanner: View {
    let text: String
    var isError = false
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? .orange : Palette.network)
                .symbolEffect(.bounce, value: text)
            Text(text).textSelection(.enabled)
            Spacer()
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(Corner.bannerPadding)
        .background((isError ? Color.orange : Palette.network).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Corner.banner, style: .continuous))
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct FullDiskAccessHint: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield").foregroundStyle(.orange)
            Text("The Trash and Mail attachments are protected. Give Luud Full Disk Access, then scan again.")
                .font(.callout)
            Spacer()
            Button("Open Settings") { SystemSettings.openFullDiskAccess() }
        }
        .padding(Corner.bannerPadding)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Corner.banner, style: .continuous))
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .medium))
                .foregroundStyle(tint.gradient)
                .symbolEffect(.breathe, options: .repeat(.continuous))
            Text(title).font(.system(.title2, design: .rounded).weight(.bold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(tint)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Small cache so list rows don't hit NSWorkspace for every redraw.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let icon = icons[url.path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url.path] = icon
        return icon
    }
}
