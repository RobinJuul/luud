// Renders Luud's app icon — the kaheksakand, the Estonian eight-pointed star — at every
// iconset size. Each size is drawn from vectors so small sizes stay crisp.
// Usage: swift make-icon.swift <output.iconset>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let pink = CGColor(red: 1.00, green: 0.30, blue: 0.55, alpha: 1)
let violet = CGColor(red: 0.48, green: 0.36, blue: 1.00, alpha: 1)
let amber = CGColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

/// Continuous-corner app body (superellipse) on the 1024 grid.
func bodyPath() -> CGPath {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGMutablePath()
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 0.4)
        let y = rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 0.4)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// A rhombus from `inner` to `outer` along `angle`, widest halfway.
func petal(center c: CGPoint, angle a: CGFloat, inner: CGFloat, outer: CGFloat, halfWidth w: CGFloat) -> CGPath {
    let mid = (inner + outer) / 2
    func pt(_ r: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * cos(a) - side * sin(a), y: c.y + r * sin(a) + side * cos(a))
    }
    let path = CGMutablePath()
    path.move(to: pt(inner, 0)); path.addLine(to: pt(mid, w)); path.addLine(to: pt(outer, 0)); path.addLine(to: pt(mid, -w))
    path.closeSubpath()
    return path
}

func drawIcon(_ ctx: CGContext) {
    let body = bodyPath()
    let c = CGPoint(x: 512, y: 512)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([CGColor(red: 0.16, green: 0.08, blue: 0.30, alpha: 1),
                                     CGColor(red: 0.07, green: 0.05, blue: 0.16, alpha: 1)]),
                           start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
    for (color, center, radius) in [(pink, CGPoint(x: 260, y: 820), 520.0), (violet, CGPoint(x: 840, y: 240), 560.0)] {
        ctx.drawRadialGradient(gradient([color.copy(alpha: 0.55)!, color.copy(alpha: 0)!]),
                               startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 600), options: [])

    let star = CGMutablePath()
    for k in 0..<8 {
        star.addPath(petal(center: c, angle: .pi / 2 - CGFloat(k) * .pi / 4, inner: 92, outer: 318, halfWidth: 58))
    }
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: pink.copy(alpha: 0.55))
    ctx.addPath(star); ctx.setFillColor(pink); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(star); ctx.setLineWidth(18); ctx.setLineJoin(.round); ctx.replacePathWithStrokedPath()
    ctx.addPath(star); ctx.clip()
    ctx.drawLinearGradient(gradient([amber, pink, violet]), start: CGPoint(x: 230, y: 830), end: CGPoint(x: 800, y: 200), options: [])
    ctx.restoreGState()

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: white.copy(alpha: 0.7))
    ctx.addPath(petal(center: c, angle: .pi / 2, inner: -52, outer: 52, halfWidth: 52))
    ctx.setLineWidth(12); ctx.setLineJoin(.round); ctx.setStrokeColor(white); ctx.setFillColor(white)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
    ctx.restoreGState()
}

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    gc.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(gc.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: output.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: output.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if CommandLine.arguments.count > 2 {
    try! render(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
