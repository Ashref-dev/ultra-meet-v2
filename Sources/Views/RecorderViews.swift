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
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.35), value: meeting.title)
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
                    if state.renamedID == meeting.id {
                        Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.orange)
                        MonoLabel("Renamed by AI", color: Theme.orange)
                    } else if let activity {
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
        .padding(.horizontal, 4).padding(.vertical, 3)
        .background(Theme.orange.opacity(state.renamedID == meeting.id ? 0.09 : 0), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, -4).padding(.vertical, -3)
        .animation(.easeInOut(duration: 0.4), value: state.renamedID)
    }
    var activity: String? {
        if meeting.id == state.activeID { return state.recorder.paused ? "Paused" : "Recording" }
        if state.queued.contains(meeting.id) { return "Waiting to transcribe" }
        if meeting.id == state.analyzingID { return "Analyzing" }
        if meeting.id == state.pendingID { return "Preparing" }
        return nil
    }
}

/// Who gets recorded: You (microphone) and Colleagues (Mac audio). Refuses, with a shake, to turn both off.
struct SourcePicker: View {
    @ObservedObject var state: AppState
    @State private var refused: CGFloat = 0
    var body: some View {
        HStack(spacing: 6) {
            SourcePill(title: "You", detail: "Microphone", symbol: "mic.fill", color: Theme.you, isOn: binding(microphone: true))
            SourcePill(title: "Colleagues", detail: "Mac audio", symbol: "speaker.wave.2.fill", color: Theme.colleagues, isOn: binding(microphone: false))
        }
        .modifier(Shake(animatableData: refused))
    }
    func binding(microphone: Bool) -> Binding<Bool> {
        let source = state.preferences.source
        return Binding(
            get: { microphone ? source.usesMicrophone : source.usesSystemAudio },
            set: { value in
                let next = microphone ? AudioSource.from(microphone: value, system: source.usesSystemAudio) : AudioSource.from(microphone: source.usesMicrophone, system: value)
                guard let next else { withAnimation(.linear(duration: 0.35)) { refused += 1 }; return }
                state.preferences.source = next
                state.savePreferences()
            })
    }
}

/// Compact source toggle: colored icon, name and a mini switch on one line.
struct SourcePill: View {
    let title: String
    let detail: String
    let symbol: String
    let color: Color
    @Binding var isOn: Bool
    @State private var hovering = false
    var body: some View {
        Button { withAnimation(Theme.feedback) { isOn.toggle() } } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isOn ? .white : Theme.secondary)
                    .frame(width: 18, height: 18)
                    .background(isOn ? color : Theme.line, in: Circle())
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(isOn ? Color.primary : Theme.secondary)
                SwitchKnob(isOn: isOn, color: color)
            }
            .padding(.leading, 5).padding(.trailing, 7).frame(height: 28)
            .background(isOn ? color.opacity(0.08) : hovering ? Theme.line.opacity(0.4) : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(isOn ? color.opacity(hovering ? 0.6 : 0.3) : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(Theme.feedback, value: hovering)
        .help(isOn ? "\(title) (\(detail)) will be recorded. Click to turn off." : "Click to record \(title.lowercased()) (\(detail)).")
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(isOn ? "Recorded" : "Not recorded")
        .accessibilityAddTraits(.isToggle)
    }
}

