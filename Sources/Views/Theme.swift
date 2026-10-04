import AppKit
import SwiftUI

enum Theme {
    static let orange = Color(nsColor: LogoGlyph.ink)
    static let ember = Color(red: 0.66, green: 0.13, blue: 0.08)
    /// Speakers: you (microphone) are green, colleagues (Mac audio) are orange.
    static let you = adaptive(light: NSColor(red: 0.10, green: 0.56, blue: 0.36, alpha: 1), dark: NSColor(red: 0.33, green: 0.78, blue: 0.53, alpha: 1))
    static let colleagues = adaptive(light: NSColor(red: 0.91, green: 0.45, blue: 0.07, alpha: 1), dark: NSColor(red: 0.98, green: 0.60, blue: 0.24, alpha: 1))
    static let readingWidth: CGFloat = 640
    static let radius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let chipRadius: CGFloat = 4
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

/// The logo mark in SwiftUI. For the full app icon use `Image(nsImage: LogoGlyph.appIcon(size:))`.
struct LogoMark: View {
    var size: CGFloat = 15
    var body: some View {
        Canvas { context, canvas in
            for dot in LogoGlyph.dots(in: CGRect(origin: .zero, size: canvas)) {
                context.fill(Path(ellipseIn: dot.rect), with: .color(Color(nsColor: dot.active ? LogoGlyph.ink : LogoGlyph.lattice)))
            }
        }
        .frame(width: size * LogoGlyph.aspect, height: size)
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
