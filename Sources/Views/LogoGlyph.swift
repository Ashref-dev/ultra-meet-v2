import AppKit

/// The Ultra Transcribe logo, defined once. The app icon (`scripts/icon/generate.sh` compiles this file),
/// the menu bar icon and every in-app mark draw from here, so they cannot drift apart.
///
/// A 7×5 dot lattice: faint dots everywhere, orange dots forming a waveform. Coordinates are y-down.
enum LogoGlyph {
    static let heights = [1, 2, 4, 3, 5, 2, 1]
    static let rows = 5
    static let ink = NSColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1)
    static let lattice = NSColor(red: 0.80, green: 0.76, blue: 0.70, alpha: 0.35)
    /// Width : height of the dot lattice.
    static let aspect = CGFloat(heights.count) / CGFloat(rows)

    struct Dot { let rect: CGRect; let active: Bool }

    /// Every dot of the lattice inside `rect`. `levels` (0…1, one per column) replaces the waveform with live audio.
    static func dots(in rect: CGRect, levels: [Double]? = nil) -> [Dot] {
        let pitch = min(rect.width / CGFloat(heights.count), rect.height / CGFloat(rows))
        let diameter = pitch * 0.7
        let origin = CGPoint(x: rect.midX - pitch * CGFloat(heights.count) / 2, y: rect.midY - pitch * CGFloat(rows) / 2)
        return heights.indices.flatMap { column -> [Dot] in
            let count = levels.map { max(1, min(rows, Int((Double(rows) * $0[column]).rounded()))) } ?? heights[column]
            let first = (rows - count) / 2
            return (0..<rows).map { row in
                Dot(rect: CGRect(x: origin.x + CGFloat(column) * pitch + (pitch - diameter) / 2, y: origin.y + CGFloat(row) * pitch + (pitch - diameter) / 2, width: diameter, height: diameter),
                    active: row >= first && row < first + count)
            }
        }
    }

    // MARK: App icon

    /// The macOS app icon at any size ("Ember"): a top-lit, shadowed orange plate on Apple's 1024 grid carrying
    /// the flat dot matrix in white. Used for AppIcon and the Credits pane.
    static func appIcon(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawIcon(context, scale: bounds.width / 1024)
            return true
        }
    }

    /// Apple's macOS icon grid: 824 pt plate, 100 pt margins, 185.4 pt corners, baked shadow (y 12, σ 16, 30%).
    private static func drawIcon(_ context: CGContext, scale s: CGFloat) {
        let plate = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
        let shape = CGPath(roundedRect: plate, cornerWidth: 185.4 * s, cornerHeight: 185.4 * s, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 12 * s), blur: 32 * s, color: NSColor(white: 0, alpha: 0.30).cgColor)
        context.addPath(shape)
        context.setFillColor(plateBottom.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        linear(context, [plateTop, plateBottom], from: plate.minY, to: plate.maxY)
        radial(context, [NSColor(white: 1, alpha: 0.35), NSColor(white: 1, alpha: 0)], center: CGPoint(x: plate.midX, y: plate.minY + plate.height * 0.1), radius: plate.width * 0.7)
        // Rim light: bright top edge, faint dark bottom edge.
        context.addPath(shape)
        context.setLineWidth(10 * s)
        context.replacePathWithStrokedPath()
        context.clip()
        linear(context, [NSColor(white: 1, alpha: 0.95), NSColor(white: 1, alpha: 0), NSColor(white: 0, alpha: 0.12)], from: plate.minY, to: plate.maxY)
        context.restoreGState()

        let width = plate.width * 0.78
        for dot in dots(in: CGRect(x: plate.midX - width / 2, y: plate.midY - width / aspect / 2, width: width, height: width / aspect)) {
            context.setFillColor(NSColor(white: 1, alpha: dot.active ? 1 : 0.2).cgColor)
            context.fillEllipse(in: dot.rect)
        }
    }

    private static let plateTop = NSColor(red: 0.96, green: 0.42, blue: 0.18, alpha: 1)
    private static let plateBottom = NSColor(red: 0.74, green: 0.18, blue: 0.05, alpha: 1)
    private static func gradient(_ colors: [NSColor]) -> CGGradient? {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors.map(\.cgColor) as CFArray, locations: nil)
    }
    private static func linear(_ context: CGContext, _ colors: [NSColor], from top: CGFloat, to bottom: CGFloat) {
        guard let gradient = gradient(colors) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: top), end: CGPoint(x: 0, y: bottom), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    private static func radial(_ context: CGContext, _ colors: [NSColor], center: CGPoint, radius: CGFloat) {
        guard let gradient = gradient(colors) else { return }
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    }
}
