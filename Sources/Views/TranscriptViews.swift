import AppKit
import SwiftUI

/// Consecutive transcript lines from the same side of the call.
struct SpeakerBlock: Identifiable {
    let source: String
    var segments: [TranscriptSegment]
    var id: UUID { segments[0].id }
    static func group(_ segments: [TranscriptSegment]) -> [SpeakerBlock] {
        segments.reduce(into: []) { blocks, segment in
            if blocks.last?.source == segment.source { blocks[blocks.count - 1].segments.append(segment) }
            else { blocks.append(SpeakerBlock(source: segment.source, segments: [segment])) }
        }
    }
}

/// What the lines of a saved transcript can do. Live and in-progress transcripts are read-only.
struct LineActions {
    var canSeek: Bool
    var canRedo: Bool
    var languages: [String]
    var seek: (TranscriptSegment) -> Void
    var redo: (TranscriptSegment, String?) -> Void
    var edit: (TranscriptSegment, String) -> Void
}

/// One speaker turn: avatar and name on top, a colored rail binding every line underneath to them.
struct SpeakerBlockView: View {
    let block: SpeakerBlock
    var playingID: UUID?
    var redoingID: UUID?
    var showLanguage = false
    var actions: LineActions?
    @State private var editingID: UUID?
    @State private var draft = ""
    @FocusState private var focused: Bool
    var body: some View {
        let color = Theme.speakerColor(block.source)
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                SpeakerAvatar(source: block.source, size: 26)
                Capsule().fill(color.opacity(0.22)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.segments[0].speaker).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
                    MonoLabel(Meeting.timestamp(block.segments[0].start))
                }
                .padding(.top, 4)
                ForEach(block.segments) { line($0, color: color) }
            }
            .padding(.bottom, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(block.segments[0].speaker)
    }
    func line(_ segment: TranscriptSegment, color: Color) -> some View {
        let alignment: Alignment = segment.isRightToLeft ? .trailing : .leading
        return HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button { actions?.seek(segment) } label: { Text(Meeting.timestamp(segment.start)).font(Theme.mono).monospacedDigit() }
                .buttonStyle(TimestampStyle()).disabled(actions?.canSeek != true).help("Play from here")
                .frame(width: 44, alignment: .leading)
            VStack(alignment: segment.isRightToLeft ? .trailing : .leading, spacing: 6) {
                if editingID == segment.id {
                    TextField("Line", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 14)).lineSpacing(5)
                        .multilineTextAlignment(segment.isRightToLeft ? .trailing : .leading)
                        .focused($focused)
                        .onSubmit { commit(segment) }
                        .onExitCommand { editingID = nil }
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.orange.opacity(0.55), lineWidth: 1.5))
                    MonoLabel("Return saves · Esc cancels")
                } else {
                    Text(segment.text)
                        .underline(segment.isUncertain, pattern: .dot, color: Theme.secondary.opacity(0.6))
                        .font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                        .foregroundStyle(segment.isUncertain ? Theme.secondary : Color.primary)
                        .multilineTextAlignment(segment.isRightToLeft ? .trailing : .leading)
                        .help(segment.isUncertain ? "The recognizer was unsure about this line. Right-click to correct it or transcribe it again." : "")
                }
                if redoingID == segment.id { DotProgress(value: nil, dots: 14).frame(width: 70, height: 4) }
            }
            .frame(maxWidth: Theme.readingWidth, alignment: alignment)
            .fixedSize(horizontal: false, vertical: true)
            if showLanguage {
                Text(segment.languageCode ?? "").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.secondary)
                    .frame(width: 24).accessibilityLabel(segment.language ?? "")
            }
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(playingID == segment.id ? color.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, -6)
        .animation(Theme.feedback, value: playingID)
        .id(segment.id)
        .contextMenu {
            if let actions {
                Button("Play from Here") { actions.seek(segment) }.disabled(!actions.canSeek)
                Button("Copy Line") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(segment.text, forType: .string)
                }
                Button("Edit Line") { draft = segment.text; editingID = segment.id; focused = true }
                Divider()
                Menu("Transcribe Again As") {
                    ForEach(actions.languages, id: \.self) { language in Button(language) { actions.redo(segment, language) } }
                    Divider()
                    Button("Detect Language") { actions.redo(segment, nil) }
                }
                .disabled(!actions.canRedo)
            }
        }
    }
    func commit(_ segment: TranscriptSegment) {
        actions?.edit(segment, draft)
        editingID = nil
    }
}

struct TimestampStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Label(configuration: configuration) }
    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label
                .foregroundStyle(hovering && enabled ? Theme.orange : Theme.secondary.opacity(0.8))
                .underline(hovering && enabled, color: Theme.orange.opacity(0.5))
                .onHover { hovering = $0 }
        }
    }
}

/// The meeting at a glance: when you (green, top row) and colleagues (orange, bottom row) spoke, with the playhead.
/// Click anywhere to play from that moment.
struct ConversationMap: View {
    let segments: [TranscriptSegment]
    let duration: Double
    var position: Double?
    var seek: ((Double) -> Void)?
    var span: Double { max(1, duration, segments.map(\.end).max() ?? 0) }
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let pitch: CGFloat = 5
                let columns = max(1, Int(size.width / pitch))
                var spoke = Array(repeating: (you: false, colleagues: false), count: columns)
                for segment in segments {
                    let first = min(columns - 1, Int(segment.start / span * Double(columns)))
                    let last = max(first, min(columns - 1, Int(segment.end / span * Double(columns))))
                    for column in first...last {
                        if segment.source == "system" { spoke[column].colleagues = true } else { spoke[column].you = true }
                    }
                }
                for column in 0..<columns {
                    let x = CGFloat(column) * pitch + 0.9
                    for (row, active, color) in [(0, spoke[column].you, Theme.you), (1, spoke[column].colleagues, Theme.colleagues)] {
                        let rect = CGRect(x: x, y: CGFloat(row) * 6 + 1, width: 3.2, height: 3.2)
                        context.fill(Path(ellipseIn: rect), with: .color(active ? color : Theme.secondary.opacity(0.13)))
                    }
                }
                if let position {
                    let x = CGFloat(position / span) * size.width
                    context.fill(Path(roundedRect: CGRect(x: x - 1, y: -1, width: 2, height: size.height + 2), cornerRadius: 1), with: .color(Theme.orange))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in seek?(Double(location.x / max(1, geometry.size.width)) * span) }
        }
        .frame(height: 12)
        .help(seek == nil ? "When each side spoke" : "When each side spoke. Click to play from there.")
        .accessibilityElement()
        .accessibilityLabel("Conversation timeline")
    }
}

/// Talk time per side, measured from the transcript.
struct TalkTimeLabels: View {
    let meeting: Meeting
    var body: some View {
        let time = meeting.talkTime
        let total = max(1, time.you + time.colleagues)
        HStack(spacing: 14) {
            if time.you > 0 { MonoLabel("You \(Meeting.timestamp(time.you)) · \(Int((time.you / total * 100).rounded()))%", color: Theme.you) }
            if time.colleagues > 0 { MonoLabel("Colleagues \(Meeting.timestamp(time.colleagues)) · \(Int((time.colleagues / total * 100).rounded()))%", color: Theme.colleagues) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A short inline message with an optional action, for hints that should not interrupt.
struct InlineHint: View {
    let symbol: String
    let text: String
    var action: (title: String, run: () -> Void)?
    var dismiss: (() -> Void)?
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.orange)
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action { Button(action.title, action: action.run).buttonStyle(ControlStyle(compact: true)) }
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Dismiss")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}
