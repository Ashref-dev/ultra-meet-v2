import AppKit
import SwiftUI

/// Versus mode (experimental): the meeting transcribed by several speech models and read side by side, one row per
/// stretch of speech, with the words a model disagrees on marked.
struct VersusView: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    let runs: [VersusRun]
    /// Why other models can't transcribe this meeting now; nil when they can.
    let blocker: String?
    /// Columns the person chose to show; nil shows the first four.
    @Binding var hidden: Set<String>?
    let clock: AudioPlayback.Clock
    let playing: Bool
    let seek: ((Double) -> Void)?
    @State private var comparison: VersusComparison?
    @State private var onlyDifferences = false
    @State private var picking = false
    @State private var clearing = false
    @State private var playingRow: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let gutter: CGFloat = 64

    var job: VersusJob? { state.versus?.meetingID == meeting.id ? state.versus : nil }
    var input: Input {
        Input(runs: runs, segments: meeting.segments, model: meeting.model, keepFrom: meeting.keepFrom, keepUntil: meeting.keepUntil,
              job: job, partial: job?.current != nil ? state.engine.partial : [])
    }
    struct Input: Equatable {
        let runs: [VersusRun]
        let segments: [TranscriptSegment]
        let model: ASRModel
        let keepFrom: Double?
        let keepUntil: Double?
        let job: VersusJob?
        let partial: [TranscriptSegment]
    }
    var body: some View {
        Group {
            if runs.isEmpty && job == nil {
                start
            } else if let comparison {
                results(comparison)
            }
        }
        .onChange(of: input, initial: true) { _, input in
            comparison = VersusComparison(columns: VersusComparison.columns(meeting: meeting, runs: input.runs, job: input.job, partial: input.partial))
        }
        .confirmationDialog("Move this comparison to the Trash?", isPresented: $clearing) {
            Button("Move to Trash", role: .destructive) { state.removeVersus(meeting.id, model: nil); hidden = nil }
        } message: { Text("Every model’s transcript of this meeting goes to the Trash. The meeting’s own transcript is not affected.") }
    }

    // MARK: Start

    var start: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "rectangle.split.3x1").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.orange)
                HStack(spacing: 8) {
                    Text("Compare speech models").font(.system(size: 18, weight: .semibold))
                    ExperimentalBadge()
                }
                Text("Each model you choose transcribes this meeting on this Mac, one after another. Then read them side by side, with the words they disagree on marked.")
                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                if let blocker {
                    InlineHint(symbol: "info.circle", text: blocker).frame(maxWidth: 440)
                } else {
                    VersusPicker(state: state, meeting: meeting, compared: []).frame(maxWidth: 460).padding(.top, 4)
                }
            }
            .padding(24).padding(.top, 24).frame(maxWidth: .infinity)
            .thinScrollbars()
        }
    }

    // MARK: Results

    func shown(_ comparison: VersusComparison) -> [VersusComparison.Column] {
        guard let hidden else { return Array(comparison.columns.prefix(4)) }
        return comparison.columns.filter { !hidden.contains($0.id) }
    }
    func results(_ comparison: VersusComparison) -> some View {
        let visible = shown(comparison)
        let compared = comparison.compared(Set(visible.map(\.id)))
        let rows = onlyDifferences && compared.count > 1 ? comparison.rows.filter { !comparison.agrees($0, among: compared) } : comparison.rows
        let shownRows = rows.filter { row in visible.contains { row.cells[$0.id] != nil } }
        return VStack(spacing: 0) {
            toolbar(comparison, visible: visible, compared: compared)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            if shownRows.isEmpty {
                                Text(onlyDifferences ? "Every shown model heard the same words." : "No lines yet.")
                                    .font(.system(size: 13)).foregroundStyle(Theme.secondary).frame(maxWidth: .infinity).padding(.vertical, 48)
                            }
                            ForEach(shownRows) { row in
                                VersusRowView(row: row, columns: visible, highlights: Dictionary(uniqueKeysWithValues: visible.map { ($0.id, comparison.unique(row, column: $0.id, among: compared)) }),
                                              playing: playingRow == row.id, seek: seek)
                                    .id(row.id)
                                Divider().opacity(0.6)
                            }
                        } header: {
                            headers(comparison, visible: visible, compared: compared)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                    .thinScrollbars()
                }
                .onChange(of: playingRow) { _, row in
                    guard let row, playing else { return }
                    withAnimation(reduceMotion ? nil : Theme.selection) { proxy.scrollTo(row, anchor: .center) }
                }
            }
        }
        .onReceive(clock.$position) { position in
            let row = playing ? comparison.rows.last(where: { $0.start <= position + 0.15 && position < $0.end + 0.6 })?.id : nil
            if row != playingRow { playingRow = row }
        }
    }
    func toolbar(_ comparison: VersusComparison, visible: [VersusComparison.Column], compared: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let job { progress(job) }
            HStack(spacing: 10) {
                if compared.count > 1 {
                    let agreeing = comparison.rows.filter { row in comparison.agrees(row, among: compared) && compared.contains { row.cells[$0] != nil } }.count
                    let heard = comparison.rows.filter { row in compared.contains { row.cells[$0] != nil } }.count
                    MonoLabel("Same words in \(agreeing) of \(heard) lines")
                        .help("Lines where every shown model heard the same words, ignoring case, accents and punctuation")
                }
                if meeting.isTrimmed {
                    MonoLabel("Kept part · \(Meeting.timestamp(meeting.keptRange.lowerBound)) to \(Meeting.timestamp(meeting.keptRange.upperBound))")
                }
                Spacer(minLength: 8)
                if compared.count > 1 {
                    Segmented(options: [(false, "All lines"), (true, "Differences")], selection: $onlyDifferences).fixedSize()
                }
                GlassControls {
                    HStack(spacing: 8) {
                        Button { picking = true } label: { Label("Add Models", systemImage: "plus") }
                            .buttonStyle(ControlStyle(compact: true))
                            .disabled(blocker != nil)
                            .help(blocker ?? "Transcribe this meeting with more models")
                            .popover(isPresented: $picking, arrowEdge: .bottom) {
                                VersusPicker(state: state, meeting: meeting, compared: Set(runs.map(\.model) + (job?.pending ?? []) + [job?.current].compactMap { $0 })) { picking = false }
                                    .padding(16).frame(width: 440)
                            }
                        MoreMenu(label: "Comparison actions") {
                            Button("Move Comparison to Trash…", role: .destructive) { clearing = true }.disabled(job?.isRunning == true || runs.isEmpty)
                        }
                    }
                }
            }
            if comparison.columns.count > 1 {
                FlowLayout(spacing: 6) {
                    ForEach(comparison.columns) { column in
                        let isShown = visible.contains { $0.id == column.id }
                        ToggleChip(title: column.title, isOn: Binding(get: { isShown }, set: { show in
                            var next = Set(comparison.columns.map(\.id)).subtracting(visible.map(\.id))
                            if show { next.remove(column.id) } else if visible.count > 1 { next.insert(column.id) }
                            hidden = next
                        }))
                        .help(isShown ? "Hide \(column.title)" : "Show \(column.title)")
                    }
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
    }
    @ViewBuilder func progress(_ job: VersusJob) -> some View {
        if job.isRunning {
            HStack(spacing: 10) {
                if let current = job.current {
                    DotProgress(value: state.engine.fraction, dots: 24).frame(width: 120, height: 5)
                    MonoLabel("\(current.fullName) · \(state.engine.message)", color: Theme.orangeText)
                } else {
                    DotProgress(value: nil, dots: 24).frame(width: 120, height: 5)
                    MonoLabel("Waits for the current recording or transcription")
                }
                if !job.pending.isEmpty { MonoLabel("· \(job.pending.count) waiting") }
                Spacer()
                Button("Stop Comparing") { state.cancelVersus() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    .help("Stops the running model and the ones waiting. Finished models are kept.")
            }
            .transition(.opacity)
        }
    }
    func headers(_ comparison: VersusComparison, visible: [VersusComparison.Column], compared: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear.frame(width: Self.gutter, height: 1)
            ForEach(visible) { column in
                VersusColumnHeader(state: state, meeting: meeting, column: column, stats: comparison.stats(column.id, among: compared), seek: seek)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 12)
        .background(Theme.paper)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// A column's model, how it did, and what can be done with it.
private struct VersusColumnHeader: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    let column: VersusComparison.Column
    let stats: VersusComparison.Stats
    let seek: ((Double) -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(column.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if !column.isMeeting {
                    MoreMenu(label: "\(column.title) actions") {
                        Button { state.preferences.model = column.model; state.savePreferences() } label: {
                            if state.preferences.model == column.model { Label("Used for New Meetings", systemImage: "checkmark") } else { Text("Use for New Meetings") }
                        }
                        .disabled(state.preferences.model == column.model)
                        Button("Transcribe Again") { state.compare(meeting.id, models: [column.model]) }
                            .disabled(state.versusUnavailable(column.model) != nil || column.status == .running || column.status == .waiting)
                        Divider()
                        Button("Remove from Comparison", role: .destructive) { state.removeVersus(meeting.id, model: column.model) }
                            .disabled(column.status == .running || column.status == .waiting)
                    }
                }
            }
            HStack(spacing: 6) {
                Text(column.subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                if !column.isMeeting && state.preferences.model == column.model {
                    MonoLabel("Default", color: Theme.orangeText).help("New meetings are transcribed with this model")
                }
            }
            status.padding(.top, 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title), \(column.subtitle)")
    }
    @ViewBuilder var status: some View {
        switch column.status {
        case .running:
            HStack(spacing: 6) {
                DotProgress(value: state.engine.fraction, dots: 12).frame(width: 54, height: 4)
                MonoLabel(column.complete ? "Again · \(Int(state.engine.fraction * 100))%" : "\(Int(state.engine.fraction * 100))%", color: Theme.orangeText)
            }
            .frame(height: 13)
        case .waiting:
            MonoLabel(column.complete ? "Waiting to run again" : "Waiting")
        case .failed(let message):
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.orange)
                Text("Failed").font(.system(size: 11.5, weight: .medium))
                Button("Try Again") { state.compare(meeting.id, models: [column.model]) }.buttonStyle(TextLinkStyle()).font(.system(size: 11.5))
                    .disabled(state.versusUnavailable(column.model) != nil)
            }
            .help(message)
        case .done:
            let details = [stats.unsure > 0 ? "\(stats.unsure) unsure" : nil, stats.missed > 0 ? "\(stats.missed) missed" : nil, column.seconds.map { "took \(VersusPicker.duration($0))" }].compactMap { $0 }
            VStack(alignment: .leading, spacing: 3) {
                MonoLabel("\(stats.lines) lines · \(stats.words) words")
                if !details.isEmpty { MonoLabel(details.joined(separator: " · ")) }
            }
            .help("Unsure: lines the model wasn’t confident about. Missed: lines only other shown models heard; a model that invents words on silence raises everyone else’s count. Time includes loading the model.")
        }
    }
}

/// One stretch of speech: when, who, and what each shown model heard, with the words only that model heard marked.
private struct VersusRowView: View {
    let row: VersusComparison.Row
    let columns: [VersusComparison.Column]
    let highlights: [String: Set<String>]
    let playing: Bool
    let seek: ((Double) -> Void)?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Button { seek?(row.start) } label: { Text(Meeting.timestamp(row.start)).font(Theme.mono).monospacedDigit() }
                    .buttonStyle(TimestampStyle()).disabled(seek == nil).help("Play from here")
                HStack(spacing: 5) {
                    Circle().fill(Theme.speakerColor(row.source)).frame(width: 6, height: 6)
                    Text(row.speaker).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.speakerText(row.source)).lineLimit(1)
                }
            }
            .frame(width: VersusView.gutter, alignment: .leading)
            ForEach(columns) { cell($0) }
        }
        .padding(.horizontal, 8).padding(.vertical, 10)
        .background(playing ? Theme.speakerColor(row.source).opacity(0.09) : hovering && seek != nil ? Theme.line.opacity(0.45) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { seek?(row.start) }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Theme.feedback, value: playing)
        .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
        .help(seek == nil ? "" : "Click to play this line")
        .contextMenu {
            Button("Play from Here") { seek?(row.start) }.disabled(seek == nil)
            Button("Copy Line from Every Model") {
                let text = columns.map { "\($0.title): \(row.text($0.id) ?? "(nothing)")" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
    @ViewBuilder func cell(_ column: VersusComparison.Column) -> some View {
        if let lines = row.cells[column.id] {
            let text = lines.map(\.text).joined(separator: " ")
            let rightToLeft = lines.first?.isRightToLeft == true
            let unsure = lines.contains(where: \.isUncertain)
            Text(Self.marked(text, words: highlights[column.id] ?? []))
                .font(.system(size: 13)).lineSpacing(4)
                .underline(unsure, pattern: .dot, color: Theme.secondary.opacity(0.6))
                .multilineTextAlignment(rightToLeft ? .trailing : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: rightToLeft ? .trailing : .leading)
                .accessibilityLabel("\(column.title): \(text)")
        } else {
            // A first run in progress hasn't reached later lines yet; everywhere else, nothing means the model heard nothing.
            let ahead = column.status == .running && !column.complete && row.start >= (column.segments.last?.end ?? 0)
            Group {
                if ahead { Text("…").font(.system(size: 13)).foregroundStyle(Theme.secondary) }
                else if column.complete || column.status == .running { Capsule().fill(Theme.secondary.opacity(0.35)).frame(width: 14, height: 1.5).padding(.top, 9) }
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(ahead ? "Not transcribed yet" : "\(column.title) heard nothing here")
                .accessibilityLabel(ahead ? "\(column.title): not transcribed yet" : "\(column.title): nothing")
        }
    }
    /// The text with words only this model heard marked, keeping its spacing and punctuation.
    static func marked(_ text: String, words: Set<String>) -> AttributedString {
        guard !words.isEmpty else { return AttributedString(text) }
        var result = AttributedString()
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            var piece = AttributedString(token)
            if VersusComparison.words(token).contains(where: words.contains) {
                piece.backgroundColor = Theme.orange.opacity(0.16)
                piece.foregroundColor = Theme.orangeText
            }
            result += piece
            token = ""
        }
        for character in text {
            if character.isWhitespace { flush(); result += AttributedString(String(character)) } else { token.append(character) }
        }
        flush()
        return result
    }
}

/// Choose downloaded models to transcribe the meeting with. Models that can't run say why.
struct VersusPicker: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    /// Models with a run already, or already in line; they start unselected.
    let compared: Set<ASRModel>
    var started: () -> Void = {}
    @State private var chosen: Set<ASRModel>?
    var available: [ASRModel] { ASRModel.allCases.filter { state.versusUnavailable($0) == nil } }
    var unavailable: [ASRModel] { ASRModel.allCases.filter { state.versusUnavailable($0) != nil } }
    /// Every available model this meeting hasn't been compared with, except the one it was transcribed with.
    var selection: Set<ASRModel> {
        chosen ?? Set(available.filter { !compared.contains($0) && $0 != meeting.model })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if available.isEmpty {
                InlineHint(symbol: "arrow.down.circle", text: "No speech model can run yet. Download models in Settings → Transcription.",
                           action: ("Open Settings", { state.showSettings(.transcription) }))
            } else {
                VStack(spacing: 2) { ForEach(available) { row($0) } }.padding(6).card()
            }
            if !unavailable.isEmpty && !available.isEmpty {
                HStack(spacing: 6) {
                    Text("\(unavailable.count) more \(unavailable.count == 1 ? "model is" : "models are") not ready to compare.")
                    Button("Open Settings") { state.showSettings(.transcription) }.buttonStyle(TextLinkStyle())
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                .help(unavailable.map { "\($0.fullName): \(state.versusUnavailable($0) ?? "")" }.joined(separator: "\n"))
            }
            if !available.isEmpty {
                HStack(spacing: 10) {
                    MonoLabel(selection.isEmpty ? "Choose at least one model" : "About \(Self.duration(selection.reduce(0) { $0 + estimate($1) })) · one model at a time")
                    Spacer()
                    Button {
                        state.compare(meeting.id, models: ASRModel.allCases.filter(selection.contains))
                        started()
                    } label: {
                        Label(selection.count == 1 ? "Compare 1 Model" : "Compare \(selection.count) Models", systemImage: "play.fill")
                    }
                    .buttonStyle(ControlStyle(kind: .primary, compact: true))
                    .disabled(selection.isEmpty)
                }
                Text("Runs on this Mac. The meeting’s own transcript doesn’t change.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }
    func row(_ model: ASRModel) -> some View {
        let on = selection.contains(model)
        return Button {
            var next = selection
            if on { next.remove(model) } else { next.insert(model) }
            chosen = next
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 14))
                    .foregroundStyle(on ? Theme.orange : Theme.secondary).contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(model.fullName).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.primary)
                        if model == meeting.model && !meeting.segments.isEmpty { MonoLabel("This meeting") }
                        if compared.contains(model) { MonoLabel("Compared", color: Theme.orangeText) }
                    }
                    Text("\(model.fullName == model.maker ? model.name : model.maker) · \(model.languages.count) languages · \(model.memoryGB.formatted(.number.precision(.fractionLength(1)))) GB memory")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                MonoLabel("≈ \(Self.duration(estimate(model)))")
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .buttonStyle(RowStyle(selected: on))
        .accessibilityLabel(model.fullName)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityAddTraits(.isToggle)
    }
    /// From the measured time for one minute of audio, model loading included.
    func estimate(_ model: ASRModel) -> Double {
        Double(model.minuteSeconds) * max(1, meeting.length / 60)
    }
    static func duration(_ seconds: Double) -> String {
        let minutes = Int((seconds / 60).rounded(.up))
        if seconds < 60 { return "\(max(1, Int(seconds.rounded()))) s" }
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }
}
