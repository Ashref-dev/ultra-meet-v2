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
    /// Languages a line can be forced into; empty when the model detects the language itself.
    var languages: [String]
    var canDetect: Bool
    var seek: (TranscriptSegment) -> Void
    var redo: (TranscriptSegment, String?) -> Void
    var edit: (TranscriptSegment, String) -> Void
    /// Sets the kept part of the meeting (see `Meeting.trim`); `nil` while it records, transcribes or is analyzed.
    var trim: ((_ from: Double?, _ until: Double?) -> Void)?
    var keepFrom: Double?
    var keepUntil: Double?
}

/// One speaker turn: avatar and name on top, a colored rail binding every line underneath to them.
struct SpeakerBlockView: View {
    let block: SpeakerBlock
    var playingID: UUID?
    var redoingID: UUID?
    var showLanguage = false
    var actions: LineActions?
    @State private var editingID: UUID?
    @State private var hoveredID: UUID?
    @State private var draft = ""
    /// Starts at the end of the line: focusing a field selects everything, and one keystroke would replace the line.
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let color = Theme.speakerColor(block.source)
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                SpeakerAvatar(source: block.source, size: 26)
                Capsule().fill(color.opacity(0.22)).frame(width: 2).frame(maxHeight: .infinity)
            }
            .frame(width: 26)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.segments[0].speaker).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.speakerText(block.source))
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
                    // Same font and position as the line, so editing looks like typing into the transcript.
                    TextField("Line", text: $draft, selection: $selection, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 14)).lineSpacing(5)
                        .multilineTextAlignment(segment.isRightToLeft ? .trailing : .leading)
                        .focused($focused)
                        .focusEffectDisabled()
                        .onSubmit { commit(segment) }
                        .onExitCommand { editingID = nil }
                        .onChange(of: focused) { _, isFocused in
                            guard editingID == segment.id else { return }
                            if isFocused { Task { @MainActor in selection = TextSelection(insertionPoint: draft.endIndex) } } else { commit(segment) }
                        }
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.orange.opacity(0.55), lineWidth: 1.5))
                        .padding(.horizontal, -6).padding(.vertical, -3)
                    MonoLabel("Return or click away saves · Esc cancels")
                } else {
                    Text(segment.text)
                        .underline(segment.isUncertain, pattern: .dot, color: Theme.secondary.opacity(0.6))
                        .font(.system(size: 14)).lineSpacing(5)
                        .foregroundStyle(segment.isUncertain ? Theme.secondary : Color.primary)
                        .multilineTextAlignment(segment.isRightToLeft ? .trailing : .leading)
                        .contentShape(Rectangle())
                        .gesture(TapGesture(count: 2).onEnded { if actions != nil { beginEditing(segment) } }
                            .exclusively(before: TapGesture().onEnded { if let actions, actions.canSeek { actions.seek(segment) } }))
                        .help(actions == nil ? "" : hint(segment))
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
        .background(playingID == segment.id ? color.opacity(0.09) : hoveredID == segment.id && actions != nil && editingID == nil ? Theme.line.opacity(0.45) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, -6)
        .onHover { inside in
            if inside { hoveredID = segment.id } else if hoveredID == segment.id { hoveredID = nil }
        }
        .animation(reduceMotion ? nil : Theme.feedback, value: playingID)
        .animation(reduceMotion ? nil : Theme.feedback, value: hoveredID)
        .id(segment.id)
        .contextMenu {
            if let actions {
                Button("Play from Here") { actions.seek(segment) }.disabled(!actions.canSeek)
                Button("Copy Line") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(segment.text, forType: .string)
                }
                Button("Edit Line") { beginEditing(segment) }
                Divider()
                if actions.languages.isEmpty {
                    Button("Transcribe Again") { actions.redo(segment, nil) }.disabled(!actions.canRedo)
                } else {
                    Menu("Transcribe Again As") {
                        ForEach(actions.languages, id: \.self) { language in Button(language) { actions.redo(segment, language) } }
                        if actions.canDetect {
                            Divider()
                            Button("Detect Language") { actions.redo(segment, nil) }
                        }
                    }
                    .disabled(!actions.canRedo)
                }
                if let trim = actions.trim {
                    Divider()
                    Button("Start Meeting Here") { trim(segment.start, actions.keepUntil) }
                    Button("End Meeting Here") { trim(actions.keepFrom, segment.end) }
                    if actions.keepFrom != nil || actions.keepUntil != nil {
                        Button("Restore Full Meeting") { trim(nil, nil) }
                    }
                }
            }
        }
    }
    func beginEditing(_ segment: TranscriptSegment) {
        draft = segment.text
        editingID = segment.id
        Task { @MainActor in focused = true }
    }
    func commit(_ segment: TranscriptSegment) {
        editingID = nil
        actions?.edit(segment, draft)
    }
    func hint(_ segment: TranscriptSegment) -> String {
        let use = actions?.canSeek == true ? "Click to play from here. Double-click to correct." : "Double-click to correct."
        return segment.isUncertain ? "The recognizer was unsure about this line. \(use)" : use
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
                .foregroundStyle(hovering && enabled ? Theme.orangeText : Theme.secondary)
                .underline(hovering && enabled, color: Theme.orange.opacity(0.5))
                .onHover { hovering = $0 }
        }
    }
}

/// The meeting at a glance: when you (green, top row) and colleagues (orange, bottom row) spoke, with the playhead.
/// Click anywhere to play from that moment. Time trimmed off is faint, and handles at the kept part's edges drag.
struct ConversationMap: View {
    let segments: [TranscriptSegment]
    let duration: Double
    var position: Double?
    var seek: ((Double) -> Void)?
    /// The kept part of a trimmed meeting; `nil` keeps all of it.
    var kept: ClosedRange<Double>?
    /// Saves new edges for the kept part; the handles show only when it is set.
    var trim: ((_ from: Double?, _ until: Double?) -> Void)?
    /// Previewed while dragging and saved once on release, so a drag writes the meeting and stales its notes once.
    @State private var drag: (start: Bool, edges: ClosedRange<Double>)?
    private static let space = "ConversationMap"
    var span: Double { max(1, duration, segments.map(\.end).max() ?? 0) }
    var saved: ClosedRange<Double> { kept ?? 0...span }
    var body: some View {
        GeometryReader { geometry in
            let edges = drag?.edges ?? saved
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
                    // Judged by the dot's center, so the faint part starts exactly at a handle.
                    let faint = !edges.contains(Double((x + 1.6) / size.width) * span)
                    for (row, active, color) in [(0, spoke[column].you, Theme.you), (1, spoke[column].colleagues, Theme.colleagues)] {
                        let rect = CGRect(x: x, y: CGFloat(row) * 6 + 1, width: 3.2, height: 3.2)
                        context.fill(Path(ellipseIn: rect), with: .color((active ? color : Theme.secondary.opacity(0.13)).opacity(faint ? 0.3 : 1)))
                    }
                }
                if let position {
                    let x = CGFloat(position / span) * size.width
                    context.fill(Path(roundedRect: CGRect(x: x - 1, y: -1, width: 2, height: size.height + 2), cornerRadius: 1), with: .color(Theme.orange))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in seek?(Double(location.x / max(1, geometry.size.width)) * span) }
            .help(seek == nil ? "When each side spoke" : "When each side spoke. Click to play from there.")
            .accessibilityElement()
            .accessibilityLabel("Conversation timeline")
            if trim != nil {
                handle(start: true, edges: edges, size: geometry.size)
                handle(start: false, edges: edges, size: geometry.size)
            }
        }
        .coordinateSpace(.named(Self.space))
        .frame(height: 12)
    }
    /// Follows the pointer's travel in the map's space, not its position, so grabbing a handle off-center never
    /// moves it. The grip lies mostly outside the kept part, so handles close together can both be grabbed.
    func handle(start: Bool, edges: ClosedRange<Double>, size: CGSize) -> some View {
        let seconds = start ? edges.lowerBound : edges.upperBound
        return TrimHandle(start: start, seconds: seconds, dragging: drag?.start == start)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                .onChanged { value in
                    let grabbed = start ? saved.lowerBound : saved.upperBound
                    drag = (start, moved(saved, start: start, to: grabbed + Double(value.translation.width / max(1, size.width)) * span))
                }
                .onEnded { _ in
                    if let drag { save(drag.edges) }
                    drag = nil
                })
            .accessibilityAdjustableAction { direction in
                // At most a hundred steps across a meeting; 5 s steps would take 720 swipes to cross an hour.
                let step = max(5, span / 100)
                save(moved(edges, start: start, to: seconds + (direction == .increment ? step : -step)))
            }
            .position(x: CGFloat(seconds / span) * size.width + (start ? -2 : 2), y: size.height / 2)
    }
    /// Keeps at least 5 s, or the current length when that is shorter, and snaps edges within a second of the
    /// start or end to it.
    func moved(_ edges: ClosedRange<Double>, start: Bool, to seconds: Double) -> ClosedRange<Double> {
        let minimum = min(5, edges.upperBound - edges.lowerBound)
        if start {
            let from = min(max(0, seconds), edges.upperBound - minimum)
            return (from < 1 ? 0 : from)...edges.upperBound
        }
        let until = max(min(span, seconds), edges.lowerBound + minimum)
        return edges.lowerBound...(until > span - 1 ? span : until)
    }
    func save(_ edges: ClosedRange<Double>) {
        guard let trim, edges != saved else { return }
        trim(edges.lowerBound, edges.upperBound)
    }
}

/// One edge of the kept part: "[" at its start, "]" at its end, and the time while it is dragged.
private struct TrimHandle: View {
    let start: Bool
    let seconds: Double
    let dragging: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Bracket(opening: start)
            .stroke(Theme.orange, style: StrokeStyle(lineWidth: hovering || dragging ? 2.5 : 2, lineCap: .round, lineJoin: .round))
            .frame(width: 4, height: 18)
            .frame(width: 12, height: 24, alignment: start ? .trailing : .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .top) {
                if dragging {
                    MonoLabel(Meeting.timestamp(seconds), color: Theme.orangeText).fixedSize().offset(y: -14).transition(.opacity)
                }
            }
            .onHover { hovering = $0 }
            .pointerStyle(.columnResize)
            .animation(reduceMotion ? nil : Theme.feedback, value: hovering || dragging)
            .help(start ? "Drag to change where the meeting starts" : "Drag to change where the meeting ends")
            .accessibilityElement()
            .accessibilityLabel(start ? "Meeting start" : "Meeting end")
            .accessibilityValue(Meeting.timestamp(seconds))
    }
}

/// A square bracket with its spine on the left edge of `rect` when opening, on the right edge when closing.
private struct Bracket: Shape {
    let opening: Bool
    func path(in rect: CGRect) -> Path {
        let spine = opening ? rect.minX : rect.maxX
        let tip = opening ? rect.maxX : rect.minX
        var path = Path()
        path.move(to: CGPoint(x: tip, y: rect.minY))
        path.addLine(to: CGPoint(x: spine, y: rect.minY))
        path.addLine(to: CGPoint(x: spine, y: rect.maxY))
        path.addLine(to: CGPoint(x: tip, y: rect.maxY))
        return path
    }
}

/// Talk time per side, measured from the transcript.
struct TalkTimeLabels: View {
    let meeting: Meeting
    var body: some View {
        let time = meeting.talkTime
        let total = max(1, time.you + time.colleagues)
        HStack(spacing: 14) {
            if time.you > 0 { MonoLabel("You \(Meeting.timestamp(time.you)) · \(Int((time.you / total * 100).rounded()))%", color: Theme.youText) }
            if time.colleagues > 0 { MonoLabel("Colleagues \(Meeting.timestamp(time.colleagues)) · \(Int((time.colleagues / total * 100).rounded()))%", color: Theme.colleaguesText) }
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
            Text(text).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 4)
            if let action { Button(action.title, action: action.run).buttonStyle(ControlStyle(compact: true)) }
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true, square: true)).help("Dismiss").accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 8)
        .background(Theme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

extension InlineHint {
    /// `AppState.error`, as the panel and the library show it: dismissible, and one click from the Settings pane it names.
    init(error: String, openSettings: @escaping (SettingsPane) -> Void, dismiss: @escaping () -> Void) {
        self.init(symbol: "exclamationmark.circle.fill", text: error,
                  action: SettingsPane.mentioned(in: error).map { pane -> (title: String, run: () -> Void) in ("Open Settings", { openSettings(pane) }) },
                  dismiss: dismiss)
    }
}

extension SettingsPane {
    /// The pane a message sends people to, written as "Settings → Recording".
    static func mentioned(in message: String) -> SettingsPane? {
        allCases.first { message.contains("Settings → \($0.title)") }
    }
}
