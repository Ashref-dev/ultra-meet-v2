import SwiftUI

/// Timer, pause and start/stop: the recorder's footer, shared by the menu-bar panel and the meeting window.
struct RecorderControls: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var recording: Bool { state.activeID != nil }
    var body: some View {
        HStack(spacing: 8) {
            Text(Meeting.timestamp(recording ? state.elapsed : 0))
                .font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit()
                .foregroundStyle(recording && !state.recorder.paused ? Color.primary : Theme.secondary)
                .contentTransition(.numericText())
                .accessibilityLabel("Elapsed time \(Meeting.timestamp(state.elapsed))")
            Spacer(minLength: 12)
            if recording {
                IconButton(symbol: state.recorder.paused ? "play.fill" : "pause.fill", label: state.recorder.paused ? "Resume recording" : "Pause recording") { state.togglePause() }
                    .disabled(state.stopping)
                Button { state.stopRecording() } label: {
                    HStack(spacing: 8) {
                        if state.stopping { ProgressView().controlSize(.mini).tint(.white) } else { RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 8, height: 8) }
                        Text(state.stopping ? "Saving" : "Stop")
                        Text(Meeting.timestamp(state.elapsed)).opacity(0.6).monospacedDigit()
                    }
                }
                .buttonStyle(ControlStyle(kind: .primary))
                .disabled(state.stopping)
                .help("Stop and transcribe (⌘⇧S)")
                .transition(.opacity)
            } else {
                Button { state.startRecording() } label: {
                    HStack(spacing: 8) {
                        if state.starting { ProgressView().controlSize(.mini).tint(.white) } else { Circle().fill(.white).frame(width: 7, height: 7) }
                        Text(state.starting ? "Starting" : "Start recording")
                    }
                }
                .buttonStyle(ControlStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!state.canStart)
                .help("Start recording now (⌘N)")
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : Theme.feedback, value: recording)
    }
}

/// Compact meeting row with live state, for the menu-bar panel and the library sidebar.
struct MeetingRow: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(meeting.title).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 4)
                Text(Meeting.timestamp(meeting.id == state.activeID ? state.elapsed : meeting.duration))
                    .font(Theme.mono).foregroundStyle(Theme.secondary).monospacedDigit()
            }
            if meeting.id == state.processingID {
                HStack(spacing: 8) {
                    DotProgress(value: state.engine.fraction, dots: 24).frame(width: 120, height: 5)
                    MonoLabel("\(Int(state.engine.fraction * 100))%", color: Theme.orange)
                }
                .frame(height: 13)
            } else {
                HStack(spacing: 6) {
                    if let activity {
                        Circle().fill(Theme.orange).frame(width: 5, height: 5)
                        MonoLabel(activity, color: Theme.orange)
                    } else {
                        MonoLabel(meeting.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        if !meeting.summary.isEmpty { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.orange).accessibilityLabel("Analyzed") }
                        if meeting.status == .failed { Image(systemName: "exclamationmark.circle").font(.system(size: 9)).foregroundStyle(Theme.colleagues).accessibilityLabel("Needs attention") }
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
    var activity: String? {
        if meeting.id == state.activeID { return state.recorder.paused ? "Paused" : "Recording" }
        if state.queued.contains(meeting.id) { return "Waiting to transcribe" }
        if meeting.id == state.analyzingID { return "Analyzing" }
        if meeting.id == state.pendingID { return "Preparing" }
        return nil
    }
}

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

/// One speaker turn: avatar and name on top, a colored rail binding every line underneath to them.
struct SpeakerBlockView: View {
    let block: SpeakerBlock
    let canSeek: Bool
    let seek: (TranscriptSegment) -> Void
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
                ForEach(block.segments) { segment in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Button { seek(segment) } label: { Text(Meeting.timestamp(segment.start)).font(Theme.mono).monospacedDigit() }
                            .buttonStyle(TimestampStyle()).disabled(!canSeek).help("Play from here")
                            .frame(width: 44, alignment: .leading)
                        Text(segment.text)
                            .font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                            .multilineTextAlignment(segment.isRightToLeft ? .trailing : .leading)
                            .frame(maxWidth: Theme.readingWidth, alignment: segment.isRightToLeft ? .trailing : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(block.segments[0].speaker)
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
