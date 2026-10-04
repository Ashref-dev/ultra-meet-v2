import AppKit

let canvas = NSImage(size: NSSize(width: 1024, height: 1024))
canvas.lockFocus()
NSColor(red: 0.965, green: 0.945, blue: 0.91, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 1024, height: 1024), xRadius: 220, yRadius: 220).fill()
for column in 0..<23 {
    let height = Int(2 + abs(sin(Double(column) * 0.55) * 5 + sin(Double(column) * 0.23) * 3))
    for row in -9...9 {
        let active = abs(row) < height
        (active ? NSColor(red: 0.88, green: 0.25, blue: 0.08, alpha: 1) : NSColor(red: 0.80, green: 0.77, blue: 0.72, alpha: 0.45)).setFill()
        let x = 160 + column * 31
        let y = 500 + row * 31
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 15, height: 15)).fill()
    }
}
canvas.unlockFocus()
if let tiff = canvas.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
