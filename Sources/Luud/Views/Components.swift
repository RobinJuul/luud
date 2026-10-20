import AppKit
import SwiftUI

/// Points for a history series: slot 0 on the left, newest on the right, smoothed through midpoints.
/// Drawn with Canvas rather than Swift Charts: one draw per tick instead of rebuilding 60 chart marks.
private func historyPath(_ values: [Double], top: Double, in rect: CGRect) -> Path {
    let slots = max(SystemStats.historyLength - 1, 1)
    let points = values.enumerated().map { index, value in
        CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(slots),
                y: rect.maxY - rect.height * CGFloat(min(max(value / max(top, .ulpOfOne), 0), 1)))
    }
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for (previous, point) in zip(points, points.dropFirst()) {
        let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
        path.addQuadCurve(to: mid, control: previous)
    }
    if let last = points.last { path.addLine(to: last) }
    return path
}

private func drawSeries(_ values: [Double], color: Color, top: Double, rect: CGRect, lineWidth: CGFloat, into context: inout GraphicsContext) {
    guard values.count > 1 else { return }
    let line = historyPath(values, top: top, in: rect)
    var area = line
    let lastX = rect.minX + rect.width * CGFloat(values.count - 1) / CGFloat(max(SystemStats.historyLength - 1, 1))
    area.addLine(to: CGPoint(x: lastX, y: rect.maxY))
    area.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    area.closeSubpath()
    context.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
                                            startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
    context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color
    /// Fixed top of the scale (1 for fractions); nil scales to the data.
    var maxValue: Double? = 1

    var body: some View {
        let top = maxValue ?? max(values.max() ?? 1, 1)
        Canvas { context, size in
            drawSeries(values, color: tint, top: top, rect: CGRect(origin: .zero, size: size).insetBy(dx: 0, dy: 1),
                       lineWidth: 1.6, into: &context)
        }
    }
}

/// Full chart for the dashboard: faint dashed grid, trailing axis labels, optional second series.
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
        Canvas { context, size in
            let labelWidth: CGFloat = 54
            let plot = CGRect(x: 0, y: 6, width: max(size.width - labelWidth, 1), height: max(size.height - 12, 1))
            for step in 0...2 {
                let fraction = Double(step) / 2
                let y = plot.maxY - plot.height * CGFloat(fraction)
                var grid = Path()
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                context.stroke(grid, with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                context.draw(Text(label(top * fraction)).font(.caption2).foregroundStyle(.tertiary),
                             at: CGPoint(x: size.width, y: y), anchor: .trailing)
            }
            for s in series {
                drawSeries(s.values, color: s.color, top: top, rect: plot, lineWidth: 2, into: &context)
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

/// Shows a page in its roomy form when it fits the height available, otherwise compact,
/// and scrolls only if even the compact form doesn't fit. Only one form is laid out at a
/// time: each form's natural height is measured while it's on screen and remembered.
struct FittingLayout<Content: View>: View {
    @ViewBuilder let content: (_ compact: Bool) -> Content
    @State private var roomyHeight: CGFloat?
    @State private var compactHeight: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size.height
            let compact = (roomyHeight ?? 0) > available
            let scrolls = compact && (compactHeight ?? 0) > available
            if scrolls {
                ScrollView { content(true) }
            } else {
                content(compact)
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
                        if compact { compactHeight = height } else { roomyHeight = height }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

/// Small cache so list rows don't hit NSWorkspace for every redraw.
@MainActor
enum IconCache {
    private static var icons: [String: NSImage] = [:]

    private static var appIcons: [pid_t: NSImage?] = [:]

    /// Icon of a running app, or nil for background processes. Cached per process.
    static func appIcon(pid: pid_t) -> NSImage? {
        if let cached = appIcons[pid] { return cached }
        let icon = NSRunningApplication(processIdentifier: pid)?.icon
        appIcons[pid] = icon
        return icon
    }

    static func icon(for url: URL) -> NSImage {
        if let icon = icons[url.path] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[url.path] = icon
        return icon
    }
}
