import AppKit
import SwiftUI

enum Theme {
    static let orange = Color(nsColor: LogoGlyph.ink)
    static let ember = Color(red: 0.66, green: 0.13, blue: 0.08)
    static let destructive = Color(nsColor: .systemRed)
    /// Speakers: you (microphone) are green, colleagues (Mac audio) are orange.
    static let you = adaptive(light: NSColor(red: 0.10, green: 0.56, blue: 0.36, alpha: 1), dark: NSColor(red: 0.33, green: 0.78, blue: 0.53, alpha: 1))
    static let colleagues = adaptive(light: NSColor(red: 0.91, green: 0.45, blue: 0.07, alpha: 1), dark: NSColor(red: 0.98, green: 0.60, blue: 0.24, alpha: 1))
    /// Deep tones for the center of the dot waveform; it fades to the speaker color at the edges, as in the reference.
    static let youDeep = adaptive(light: NSColor(red: 0.03, green: 0.34, blue: 0.21, alpha: 1), dark: NSColor(red: 0.12, green: 0.55, blue: 0.34, alpha: 1))
    static let colleaguesDeep = adaptive(light: NSColor(red: 0.70, green: 0.15, blue: 0.09, alpha: 1), dark: NSColor(red: 0.86, green: 0.29, blue: 0.16, alpha: 1))
    static let readingWidth: CGFloat = 640
    static let radius: CGFloat = 16
    static let controlRadius: CGFloat = 10
    static let chipRadius: CGFloat = 5
    static let controlHeight: CGFloat = 34
    static let compactControlHeight: CGFloat = 28
    static let swipeActionSize: CGFloat = 36
    static let feedback = Animation.easeOut(duration: 0.16)
    static let selection = Animation.snappy(duration: 0.24, extraBounce: 0)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let paper = Color(nsColor: .textBackgroundColor)
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let line = Color(nsColor: .separatorColor)
    static let selectionFill = orange.opacity(0.12)
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
