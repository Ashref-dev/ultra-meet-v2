import AppKit

// Draws the app icon from the same 7-column dot glyph as `LogoGlyph` in Sources/Views/Theme.swift.
let heights = [1, 2, 4, 3, 5, 2, 1]
let rows = 5
let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.18)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 24
shadow.set()
NSColor(red: 0.975, green: 0.962, blue: 0.94, alpha: 1).setFill()
NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185).fill()
NSGraphicsContext.current?.restoreGraphicsState()
let pitch: CGFloat = 92
let dot: CGFloat = 64
let origin = CGPoint(x: 512 - pitch * CGFloat(heights.count) / 2, y: 512 - pitch * CGFloat(rows) / 2)
for (column, height) in heights.enumerated() {
    let first = (rows - height) / 2
    for row in 0..<rows {
        let active = row >= first && row < first + height
        (active ? NSColor(red: 0.85, green: 0.25, blue: 0.08, alpha: 1) : NSColor(red: 0.80, green: 0.76, blue: 0.70, alpha: 0.35)).setFill()
        let x = origin.x + CGFloat(column) * pitch + (pitch - dot) / 2
        let y = origin.y + CGFloat(rows - 1 - row) * pitch + (pitch - dot) / 2
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dot, height: dot)).fill()
    }
}
canvas.unlockFocus()
if let tiff = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
