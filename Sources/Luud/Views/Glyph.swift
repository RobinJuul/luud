import AppKit

/// The kaheksakand star as a one-color template image, so the menu bar tints it like system icons.
enum Glyph {
    static let menuBar: NSImage = {
        let size: CGFloat = 16
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let c = CGPoint(x: size / 2, y: size / 2)
            let path = CGMutablePath()
            func petal(_ angle: CGFloat, inner: CGFloat, outer: CGFloat, half: CGFloat) {
                let mid = (inner + outer) / 2
                func pt(_ r: CGFloat, _ side: CGFloat) -> CGPoint {
                    CGPoint(x: c.x + r * cos(angle) - side * sin(angle), y: c.y + r * sin(angle) + side * cos(angle))
                }
                path.move(to: pt(inner, 0)); path.addLine(to: pt(mid, half))
                path.addLine(to: pt(outer, 0)); path.addLine(to: pt(mid, -half)); path.closeSubpath()
            }
            // The center diamond keeps eight petals from reading as the system loading spinner.
            for k in 0..<8 {
                petal(.pi / 2 - CGFloat(k) * .pi / 4, inner: 3.2, outer: 8.0, half: 1.8)
            }
            petal(.pi / 2, inner: -2.0, outer: 2.0, half: 2.0)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
