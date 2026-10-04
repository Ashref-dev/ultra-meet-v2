import AppKit
import SwiftUI

enum Theme {
    static let orange = Color(red: 0.85, green: 0.25, blue: 0.08)
    static let ember = Color(red: 0.66, green: 0.13, blue: 0.08)
    /// Speakers: you (microphone) are green, colleagues (Mac audio) are orange.
    static let you = adaptive(light: NSColor(red: 0.10, green: 0.56, blue: 0.36, alpha: 1), dark: NSColor(red: 0.33, green: 0.78, blue: 0.53, alpha: 1))
    static let colleagues = adaptive(light: NSColor(red: 0.91, green: 0.45, blue: 0.07, alpha: 1), dark: NSColor(red: 0.98, green: 0.60, blue: 0.24, alpha: 1))
    static let readingWidth: CGFloat = 640
    static let radius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let feedback = Animation.easeOut(duration: 0.16)
    static let selection = Animation.snappy(duration: 0.24, extraBounce: 0)
    static let background = adaptive(light: NSColor(red: 0.965, green: 0.955, blue: 0.94, alpha: 1), dark: NSColor(red: 0.11, green: 0.105, blue: 0.10, alpha: 1))
    static let paper = adaptive(light: .white, dark: NSColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
    static let secondary = adaptive(light: NSColor(red: 0.43, green: 0.39, blue: 0.35, alpha: 1), dark: NSColor(red: 0.73, green: 0.70, blue: 0.66, alpha: 1))
    static let line = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.10))
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static func speakerColor(_ source: String) -> Color {
        switch source {
        case "microphone": return you
        case "system": return colleagues
        default: return secondary
        }
    }
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }))
    }
}

/// The Ultra Transcribe mark: columns of dots shaped like a waveform. Shared by the menu bar icon and the UI.
enum LogoGlyph {
    static let heights = [1, 2, 4, 3, 5, 2, 1]
    static let rows = 5
    /// Calls `fill` for every dot. When `levels` (0…1, one per column) is given, columns follow live audio instead.
    static func draw(in rect: CGRect, levels: [Double]? = nil, fill: (CGRect) -> Void) {
        let pitch = rect.width / CGFloat(heights.count)
        let rowPitch = rect.height / CGFloat(rows)
        let dot = min(pitch, rowPitch) * 0.78
        for (column, height) in heights.enumerated() {
            let count = levels.map { max(1, min(rows, Int((Double(rows) * $0[column]).rounded()))) } ?? height
            let firstRow = (rows - count) / 2
            for row in firstRow..<(firstRow + count) {
                fill(CGRect(x: rect.minX + CGFloat(column) * pitch + (pitch - dot) / 2, y: rect.minY + CGFloat(row) * rowPitch + (rowPitch - dot) / 2, width: dot, height: dot))
            }
        }
    }
}

struct LogoMark: View {
    var size: CGFloat = 15
    var color: Color = Theme.orange
    var body: some View {
        Canvas { context, canvas in
            LogoGlyph.draw(in: CGRect(origin: .zero, size: canvas)) { context.fill(Path(ellipseIn: $0), with: .color(color)) }
        }
        .frame(width: size * 1.4, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusBadge: View {
    let meeting: Meeting
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(meeting.status == .recording ? Theme.orange : meeting.status == .failed ? Theme.colleagues : Theme.secondary.opacity(0.6)).frame(width: 5, height: 5)
            MonoLabel(label)
        }
    }
    var label: String {
        switch meeting.status {
        case .importing: return "Importing"
        case .recording: return "Recording"
        case .processing: return "Transcribing"
        case .ready: return "Saved locally"
        case .failed: return "Needs attention"
        case .interrupted: return "Audio saved"
        }
    }
}
