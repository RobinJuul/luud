import SwiftUI

/// Corner radii follow Apple's concentricity rule: a nested shape's radius is its
/// container's radius minus the padding between them, so the curves stay parallel.
enum Corner {
    static let panel: CGFloat = 26
    static let panelPadding: CGFloat = 16
    static let banner: CGFloat = 18
    static let bannerPadding: CGFloat = 12

    static func inner(_ outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(outer - padding, 2)
    }
}

/// Live values change every second, so transitions must finish well inside that window
/// or the display never goes idle.
enum Motion {
    static let live = Animation.easeOut(duration: 0.3)
}

/// One color per metric, used consistently across the menu bar, dashboard and charts.
enum Palette {
    static let cpu = Color(red: 0.13, green: 0.76, blue: 0.90)
    static let memory = Color(red: 0.55, green: 0.36, blue: 0.96)
    static let disk = Color(red: 0.96, green: 0.65, blue: 0.14)
    static let network = Color(red: 0.20, green: 0.83, blue: 0.60)
    static let upload = Color(red: 0.36, green: 0.62, blue: 1.00)
    static let brandPink = Color(red: 1.00, green: 0.30, blue: 0.55)
    static let brandViolet = Color(red: 0.48, green: 0.36, blue: 1.00)
    static let danger = Color(red: 1.00, green: 0.33, blue: 0.33)

    static let brandGradient = LinearGradient(colors: [brandPink, brandViolet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

extension AppSection {
    /// Three tints that drive the section's animated header backdrop.
    var backdrop: [Color] {
        switch self {
        case .smartCare: [Palette.brandPink, Palette.brandViolet, .orange]
        case .dashboard: [Palette.cpu, Palette.memory, Palette.network]
        case .cleanup: [Palette.network, Palette.cpu, .mint]
        case .uninstaller: [Palette.disk, Palette.brandPink, .orange]
        case .spaceLens: [Palette.memory, Palette.brandViolet, Palette.brandPink]
        case .largeFiles: [.teal, Palette.cpu, Palette.upload]
        case .performance: [.yellow, Palette.disk, .orange]
        case .settings: [.gray, Palette.upload, .indigo]
        }
    }
}

/// A mesh gradient that drifts while work is in progress and rests otherwise; frozen under Reduce Motion.
struct LiveBackdrop: View {
    let colors: [Color]
    var speed: Double = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Drifts only while work is in progress (speed > 1); at rest it holds still and costs nothing.
        let animating = speed > 1 && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animating)) { context in
            let t = context.date.timeIntervalSinceReferenceDate * speed
            MeshGradient(width: 3, height: 3, points: points(at: t), colors: meshColors)
        }
        .drawingGroup()
    }

    private func points(at t: Double) -> [SIMD2<Float>] {
        func drift(_ phase: Double, _ amplitude: Double) -> Float {
            Float(0.5 + amplitude * sin(t + phase))
        }
        return [
            [0, 0], [drift(0.3, 0.3), 0], [1, 0],
            [0, drift(1.1, 0.3)], [drift(2.0, 0.25), drift(2.9, 0.25)], [1, drift(3.7, 0.3)],
            [0, 1], [drift(4.4, 0.3), 1], [1, 1],
        ]
    }

    private var meshColors: [Color] {
        let base: Color = colorScheme == .dark ? .black : .white
        let c = colors + Array(repeating: colors.last ?? .gray, count: max(0, 3 - colors.count))
        let soft = colorScheme == .dark ? 0.55 : 0.45
        return [
            c[0], c[1].mix(with: base, by: soft), c[2],
            c[1].mix(with: base, by: soft), c[0].mix(with: c[2], by: 0.5), c[1],
            c[2].mix(with: base, by: soft), c[0], c[1].mix(with: base, by: soft),
        ]
    }
}

/// Concentric live rings, outermost first.
struct VitalsRings: View {
    struct Ring: Identifiable {
        let id: String
        let value: Double
        let color: Color
    }

    let rings: [Ring]
    var lineWidth: CGFloat = 14
    var gap: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + gap) + lineWidth / 2
                let value = min(max(ring.value, 0.002), 1)
                Circle()
                    .stroke(ring.color.opacity(0.16), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        AngularGradient(colors: [ring.color.opacity(0.65), ring.color],
                                        center: .center, startAngle: .zero, endAngle: .degrees(360 * value)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .animation(Motion.live, value: value)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Render on the GPU; conic gradients are otherwise rasterized on the CPU every frame.
        .drawingGroup()
    }
}

/// A number that rolls digit-by-digit when it changes.
struct LiveValue: View {
    let text: String
    let value: Double
    var size: CGFloat = 28
    var weight: Font.Weight = .bold

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText(value: value))
            .animation(Motion.live, value: value)
    }
}

/// Rotating highlight used to show that a scan is running.
struct SweepRing: View {
    let color: Color
    var lineWidth: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let angle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 360
            Circle()
                .stroke(
                    AngularGradient(colors: [color.opacity(0), color], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(angle))
        }
        .drawingGroup()
    }
}
