import AppKit
import SwiftUI

enum Theme {
    static let orange = Color(nsColor: LogoGlyph.ink)
    static let ember = Color(red: 0.66, green: 0.13, blue: 0.08)
    static let destructive = adaptive(light: NSColor(red: 0.78, green: 0.20, blue: 0.14, alpha: 1), dark: NSColor(red: 0.95, green: 0.42, blue: 0.34, alpha: 1))
    /// Speakers: you (microphone) are green, colleagues (Mac audio) are orange.
    static let you = adaptive(light: NSColor(red: 0.10, green: 0.56, blue: 0.36, alpha: 1), dark: NSColor(red: 0.33, green: 0.78, blue: 0.53, alpha: 1))
    static let colleagues = adaptive(light: NSColor(red: 0.91, green: 0.45, blue: 0.07, alpha: 1), dark: NSColor(red: 0.98, green: 0.60, blue: 0.24, alpha: 1))
    /// Deep tones for the center of the dot waveform; it fades to the speaker color at the edges, as in the reference.
    static let youDeep = adaptive(light: NSColor(red: 0.03, green: 0.34, blue: 0.21, alpha: 1), dark: NSColor(red: 0.12, green: 0.55, blue: 0.34, alpha: 1))
    static let colleaguesDeep = adaptive(light: NSColor(red: 0.70, green: 0.15, blue: 0.09, alpha: 1), dark: NSColor(red: 0.86, green: 0.29, blue: 0.16, alpha: 1))
    static let readingWidth: CGFloat = 640
    /// Cards and sections.
    static let radius: CGFloat = 12
    /// Buttons, fields, rows, tabs, segmented controls and chips.
    static let controlRadius: CGFloat = 8
    /// Key caps and small tags.
    static let chipRadius: CGFloat = 5
    static let controlHeight: CGFloat = 30
    static let compactControlHeight: CGFloat = 26
    static let swipeActionSize: CGFloat = 32
    static let feedback = Animation.easeOut(duration: 0.16)
    static let selection = Animation.snappy(duration: 0.24, extraBounce: 0)
    static let backgroundColor = NSColor(name: nil) { $0.isDark ? NSColor(red: 0.11, green: 0.105, blue: 0.10, alpha: 1) : NSColor(red: 0.965, green: 0.955, blue: 0.94, alpha: 1) }
    static let background = Color(nsColor: backgroundColor)
    static let paper = adaptive(light: .white, dark: NSColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1))
    static let secondary = adaptive(light: NSColor(red: 0.43, green: 0.39, blue: 0.35, alpha: 1), dark: NSColor(red: 0.73, green: 0.70, blue: 0.66, alpha: 1))
    static let line = adaptive(light: NSColor(white: 0, alpha: 0.09), dark: NSColor(white: 1, alpha: 0.10))
    static let selectionFill = orange.opacity(0.12)
    /// Tint of the panel's clear glass: lighter in light mode, darker in dark mode, see-through in both.
    static let glassTint = adaptive(light: NSColor(white: 1, alpha: 0.3), dark: NSColor(white: 0, alpha: 0.4))
    static let controlShadow = Color.black.opacity(0.08)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static func speakerColor(_ source: String) -> Color {
        switch source {
        case "microphone": return you
        case "system": return colleagues
        default: return secondary
        }
    }
    /// Deep and light shade of a speaker, for two-tone gradients.
    static func shades(_ source: String) -> (deep: Color, light: Color) {
        source == "microphone" ? (youDeep, you) : (colleaguesDeep, colleagues)
    }
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.isDark ? dark : light })
    }
}

private extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
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
