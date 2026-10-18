// Renders logo concepts for Luud. Usage: swift render-concepts.swift <output-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let S: CGFloat = 1024
let pink = CGColor(red: 1.00, green: 0.30, blue: 0.55, alpha: 1)
let violet = CGColor(red: 0.48, green: 0.36, blue: 1.00, alpha: 1)
let amber = CGColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1)
let cyan = CGColor(red: 0.13, green: 0.76, blue: 0.90, alpha: 1)
let white = CGColor(gray: 1, alpha: 1)

/// Apple-style continuous-corner app body (superellipse) on the 1024 grid.
func bodyPath() -> CGPath {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGMutablePath()
    let n: CGFloat = 5
    for i in 0...720 {
        let t = CGFloat(i) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + rect.width / 2 * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = rect.midY + rect.height / 2 * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
}

func drawBackground(_ ctx: CGContext) {
    let body = bodyPath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    ctx.drawLinearGradient(gradient([CGColor(red: 0.16, green: 0.08, blue: 0.30, alpha: 1),
                                     CGColor(red: 0.07, green: 0.05, blue: 0.16, alpha: 1)]),
                           start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    // Soft colored glows, echoing the app's mesh backdrop.
    for (color, center, radius) in [(pink, CGPoint(x: 260, y: 820), 520.0), (violet, CGPoint(x: 840, y: 240), 560.0)] {
        ctx.drawRadialGradient(gradient([color.copy(alpha: 0.55)!, color.copy(alpha: 0)!]),
                               startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }
    // Top sheen.
    ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0.10), CGColor(gray: 1, alpha: 0)]),
                           start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 600), options: [])
    ctx.restoreGState()
}

/// Strokes a path with a linear gradient.
func strokeGradient(_ ctx: CGContext, _ path: CGPath, width: CGFloat, colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.replacePathWithStrokedPath(); ctx.clip()
    ctx.drawLinearGradient(gradient(colors), start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func sparkle(_ ctx: CGContext, at p: CGPoint, size r: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: p.x, y: p.y + r))
    path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: p)
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: p)
    path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: p)
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: p)
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}

// MARK: Concept A1 — kaheksakand as eight diamond petals (as on Estonian mittens), colors sweeping around

func petal(center c: CGPoint, angle a: CGFloat, inner: CGFloat, outer: CGFloat, halfWidth w: CGFloat) -> CGPath {
    // A rhombus from near the center out to the tip, widest in the middle.
    let mid = (inner + outer) / 2
    func pt(_ r: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * cos(a) - side * sin(a), y: c.y + r * sin(a) + side * cos(a))
    }
    let path = CGMutablePath()
    path.move(to: pt(inner, 0)); path.addLine(to: pt(mid, w)); path.addLine(to: pt(outer, 0)); path.addLine(to: pt(mid, -w))
    path.closeSubpath()
    return path
}

func conceptA1(_ ctx: CGContext) {
    let c = CGPoint(x: 512, y: 512)
    let colors = [amber, pink, CGColor(red: 0.85, green: 0.33, blue: 0.80, alpha: 1), violet]
    for k in 0..<8 {
        let a = CGFloat.pi / 2 - CGFloat(k) * .pi / 4
        let path = petal(center: c, angle: a, inner: 40, outer: 300, halfWidth: 66)
        // Color sweeps clockwise from amber at the top round to violet.
        let t = CGFloat(k) / 7
        let i = min(Int(t * 3), 2), f = t * 3 - CGFloat(i)
        let from = colors[i].components!, to = colors[i + 1].components!
        let color = CGColor(red: from[0] + (to[0] - from[0]) * f, green: from[1] + (to[1] - from[1]) * f,
                            blue: from[2] + (to[2] - from[2]) * f, alpha: 1)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 30, color: color.copy(alpha: 0.55))
        ctx.addPath(path)
        ctx.setLineJoin(.round); ctx.setLineWidth(22); ctx.setStrokeColor(color); ctx.setFillColor(color)
        ctx.drawPath(using: .fillStroke)   // the stroke rounds the petal corners
        ctx.restoreGState()
    }
    // Small diamond of light at the center.
    ctx.addPath(petal(center: c, angle: .pi / 2, inner: -46, outer: 46, halfWidth: 46))
    ctx.setFillColor(white); ctx.fillPath()
}

// MARK: Concept A3 — separated petals around a center diamond, one continuous color flow

func starPetals(_ c: CGPoint) -> CGPath {
    let star = CGMutablePath()
    for k in 0..<8 {
        star.addPath(petal(center: c, angle: .pi / 2 - CGFloat(k) * .pi / 4, inner: 92, outer: 318, halfWidth: 58))
    }
    return star
}

func conceptA3(_ ctx: CGContext) {
    let c = CGPoint(x: 512, y: 512)
    let star = starPetals(c)
    // Glow first, then the petals filled with one diagonal gradient, corners softened by a matching stroke.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 46, color: pink.copy(alpha: 0.55))
    ctx.addPath(star); ctx.setFillColor(pink); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(star); ctx.setLineWidth(18); ctx.setLineJoin(.round); ctx.replacePathWithStrokedPath()
    ctx.addPath(star); ctx.clip()
    ctx.drawLinearGradient(gradient([amber, pink, violet]), start: CGPoint(x: 230, y: 830), end: CGPoint(x: 800, y: 200), options: [])
    ctx.restoreGState()
    // Center diamond, the "clean" spot the petals sweep away from.
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: white.copy(alpha: 0.7))
    let center = petal(center: c, angle: .pi / 2, inner: -52, outer: 52, halfWidth: 52)
    ctx.addPath(center); ctx.setLineWidth(12); ctx.setLineJoin(.round); ctx.setStrokeColor(white); ctx.setFillColor(white)
    ctx.drawPath(using: .fillStroke)
    ctx.restoreGState()
}

// MARK: Concept B — the app's live rings, the outer one sweeping and lifting dust

func conceptB(_ ctx: CGContext) {
    let c = CGPoint(x: 512, y: 500)
    let rings: [(CGFloat, CGColor, CGFloat)] = [(250, cyan, 0.78), (178, violet, 0.62), (106, amber, 0.45)]
    for (radius, color, fraction) in rings {
        let track = CGMutablePath(); track.addArc(center: c, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.addPath(track); ctx.setStrokeColor(color.copy(alpha: 0.16)!); ctx.setLineWidth(52); ctx.strokePath()
        let start = CGFloat.pi / 2, end = start - fraction * 2 * .pi
        let arc = CGMutablePath(); arc.addArc(center: c, radius: radius, startAngle: start, endAngle: end, clockwise: true)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 24, color: color.copy(alpha: 0.7))
        ctx.addPath(arc); ctx.setStrokeColor(color); ctx.setLineWidth(52); ctx.setLineCap(.round); ctx.strokePath()
        ctx.restoreGState()
    }
    // Dust lifting off where the outer ring's head sweeps.
    let head = CGPoint(x: c.x + 250 * cos(.pi / 2 - 0.78 * 2 * .pi), y: c.y + 250 * sin(.pi / 2 - 0.78 * 2 * .pi))
    sparkle(ctx, at: CGPoint(x: head.x - 70, y: head.y + 120), size: 46, color: white)
    sparkle(ctx, at: CGPoint(x: head.x + 10, y: head.y + 210), size: 26, color: white.copy(alpha: 0.85)!)
    sparkle(ctx, at: CGPoint(x: head.x - 150, y: head.y + 200), size: 18, color: white.copy(alpha: 0.7)!)
}

// MARK: Concept C — the kratt, the folklore helper built from household things

func conceptC(_ ctx: CGContext) {
    let x: CGFloat = 512
    // Bristle skirt: a fan of swept strokes.
    for i in 0..<9 {
        let t = CGFloat(i) / 8 - 0.5
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x + t * 60, y: 420))
        p.addQuadCurve(to: CGPoint(x: x + t * 330, y: 210), control: CGPoint(x: x + t * 120, y: 300))
        strokeGradient(ctx, p, width: 26, colors: [pink, amber], from: CGPoint(x: 0, y: 420), to: CGPoint(x: 0, y: 210))
    }
    // Binding band.
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - 70, y: 410, width: 140, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil))
    ctx.setFillColor(violet); ctx.fillPath()
    // Handle body.
    let body = CGMutablePath(); body.move(to: CGPoint(x: x, y: 452)); body.addLine(to: CGPoint(x: x, y: 640))
    strokeGradient(ctx, body, width: 34, colors: [violet, pink], from: CGPoint(x: 0, y: 452), to: CGPoint(x: 0, y: 640))
    // Arms: one raised, mid-wave.
    let arms = CGMutablePath()
    arms.move(to: CGPoint(x: x - 150, y: 560)); arms.addLine(to: CGPoint(x: x, y: 590))
    arms.addLine(to: CGPoint(x: x + 140, y: 700))
    strokeGradient(ctx, arms, width: 30, colors: [pink, violet], from: CGPoint(x: x - 150, y: 0), to: CGPoint(x: x + 140, y: 0))
    // Head: an upturned pot, with two bright eyes.
    ctx.addEllipse(in: CGRect(x: x - 92, y: 640, width: 184, height: 184))
    ctx.setFillColor(CGColor(red: 0.98, green: 0.62, blue: 0.20, alpha: 1)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: x - 110, y: 790, width: 220, height: 34), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setFillColor(CGColor(red: 0.85, green: 0.45, blue: 0.15, alpha: 1)); ctx.fillPath()
    for dx in [-36.0, 36.0] {
        ctx.addEllipse(in: CGRect(x: x + dx - 15, y: 712, width: 30, height: 30))
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fillPath()
    }
    sparkle(ctx, at: CGPoint(x: x + 200, y: 760), size: 34, color: white)
}

func render(_ name: String, _ draw: (CGContext) -> Void) -> NSImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext
    drawBackground(ctx)
    ctx.saveGState(); ctx.addPath(bodyPath()); ctx.clip()
    draw(ctx)
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(name).png"))
    let image = NSImage(size: NSSize(width: S, height: S)); image.addRepresentation(rep)
    return image
}

let concepts = [("A1-kaheksakand-petals", conceptA1), ("A3-kaheksakand-refined", conceptA3)].map { ($0.0, render($0.0, $0.1)) }

// Comparison sheet: each concept large, then at Dock (128), Finder (64) and list (32) sizes, on light and dark.
let sheetW: CGFloat = 1500, rowH: CGFloat = 420
let sheet = NSImage(size: NSSize(width: sheetW, height: rowH * 2))
sheet.lockFocus()
for (row, (_, image)) in concepts.enumerated() {
    let y = rowH * CGFloat(1 - row)
    NSColor(white: 0.93, alpha: 1).setFill(); NSRect(x: 0, y: y, width: sheetW / 2, height: rowH).fill()
    NSColor(white: 0.12, alpha: 1).setFill(); NSRect(x: sheetW / 2, y: y, width: sheetW / 2, height: rowH).fill()
    image.draw(in: NSRect(x: 20, y: y + 20, width: 380, height: 380))
    var x: CGFloat = 430
    for size in [128.0, 64.0, 32.0, 16.0] {
        image.draw(in: NSRect(x: x, y: y + rowH / 2 - size / 2, width: size, height: size)); x += size + 30
    }
    x = sheetW / 2 + 60
    for size in [128.0, 64.0, 32.0, 16.0] {
        image.draw(in: NSRect(x: x, y: y + rowH / 2 - size / 2, width: size, height: size)); x += size + 30
    }
}
sheet.unlockFocus()
let sheetRep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
try! sheetRep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("sheet.png"))
print("ok")
