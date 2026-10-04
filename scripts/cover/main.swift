import AppKit

// Renders docs/cover.png (1600 × 1200, 4:3) for the README. Run scripts/cover/generate.sh.
let width: CGFloat = 1600
let height: CGFloat = 1200
let paper = NSColor(red: 0.965, green: 0.955, blue: 0.94, alpha: 1)
let text = NSColor(red: 0.16, green: 0.14, blue: 0.12, alpha: 1)
let muted = NSColor(red: 0.43, green: 0.39, blue: 0.35, alpha: 1)
// Speaker colors, matching Theme.you and Theme.colleagues in light mode.
let you = NSColor(red: 0.10, green: 0.56, blue: 0.36, alpha: 1)
let colleagues = NSColor(red: 0.91, green: 0.45, blue: 0.07, alpha: 1)

func draw(_ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, mono: Bool = false, centerX: CGFloat, y: CGFloat, kern: CGFloat = 0) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    attributed.draw(at: CGPoint(x: centerX - attributed.size().width / 2, y: y))
}

/// A dot-matrix waveform: You speaks first, then colleagues, then both, like a real conversation.
func waveform(in rect: CGRect) {
    let pitch: CGFloat = 16
    let columns = Int(rect.width / pitch)
    let rows = 9
    var seed: UInt64 = 7
    func noise() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) }
    for column in 0..<columns {
        let t = Double(column) / Double(columns)
        let speaker = t < 0.36 ? you : t < 0.72 ? colleagues : (Int(t * 40) % 2 == 0 ? you : colleagues)
        let envelope = sin(t * .pi) * 0.75 + 0.25
        let level = min(1, envelope * (0.35 + 0.65 * noise()))
        let reach = level * Double(rows) / 2
        for row in 0..<rows {
            let distance = abs(Double(row) - Double(rows - 1) / 2)
            let active = distance <= reach
            (active ? speaker.withAlphaComponent(1 - distance / Double(rows) * 0.9) : muted.withAlphaComponent(0.12)).setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.minX + CGFloat(column) * pitch + 4, y: rect.minY + CGFloat(row) * pitch + 4, width: 8, height: 8)).fill()
        }
    }
}

/// "● YOU    ● COLLEAGUES", measured and centered as one row.
func legend(centerX: CGFloat, y: CGFloat) {
    let font = NSFont.monospacedSystemFont(ofSize: 17, weight: .semibold)
    let items = [("YOU", you), ("COLLEAGUES", colleagues)].map { label, color in
        (NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color, .kern: 1.5]), color)
    }
    let dot: CGFloat = 12, gap: CGFloat = 12, spacing: CGFloat = 56
    let total = items.reduce(0) { $0 + dot + gap + $1.0.size().width } + spacing * CGFloat(items.count - 1)
    var x = centerX - total / 2
    for (label, color) in items {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: x, y: y + (label.size().height - dot) / 2, width: dot, height: dot)).fill()
        label.draw(at: CGPoint(x: x + dot + gap, y: y))
        x += dot + gap + label.size().width + spacing
    }
}

let cover = NSImage(size: NSSize(width: width, height: height), flipped: true) { bounds in
    paper.setFill()
    bounds.fill()
    LogoGlyph.appIcon(size: 340).draw(in: CGRect(x: width / 2 - 170, y: 130, width: 340, height: 340))
    draw("Ultra Transcribe", size: 88, weight: .semibold, color: text, centerX: width / 2, y: 470, kern: -2.5)
    draw("Meeting notes for the AI-native era.", size: 34, weight: .regular, color: muted, centerX: width / 2, y: 590, kern: -0.4)
    waveform(in: CGRect(x: 160, y: 700, width: 1280, height: 150))
    legend(centerX: width / 2, y: 885)
    draw("RECORD FROM THE MENU BAR  ·  TRANSCRIBE ON YOUR MAC  ·  AI NOTES ON DEMAND", size: 18, weight: .medium, color: muted, mono: true, centerX: width / 2, y: 1040, kern: 1.6)
    return true
}

guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
cover.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
