import CoreAudio
import SwiftUI

/// Timer, pause and start/stop: the recorder's footer, shared by the menu-bar panel and the meeting window.
struct RecorderControls: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var recording: Bool { state.activeID != nil }
    var body: some View {
        HStack(spacing: 10) {
            ElapsedReader(clock: state.clock) { seconds in
                let shown = Meeting.timestamp(recording ? seconds : 0)
                Text(shown)
                    .font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.primary)
                    .opacity(recording && !state.recorder.paused ? 1 : 0.55)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Elapsed time \(shown)")
            }
            Spacer(minLength: 12)
            GlassControls {
                HStack(spacing: 8) {
                    if recording {
                        IconButton(symbol: state.recorder.paused ? "play.fill" : "pause.fill", label: state.recorder.paused ? "Resume recording" : "Pause recording") { state.togglePause() }
                            .disabled(state.stopping)
                        Button { state.stopRecording() } label: {
                            RecordLabel(title: state.stopping ? "Saving" : "Stop", busy: state.stopping) {
                                RoundedRectangle(cornerRadius: 1.5).fill(.white).frame(width: 8, height: 8)
                            }
                        }
                        .buttonStyle(ControlStyle(kind: .primary))
                        .disabled(state.stopping)
                        .help("Stop and transcribe (⌘⇧S)")
                        .transition(.opacity)
                    } else {
                        Button { state.startRecording() } label: {
                            RecordLabel(title: state.starting ? "Starting" : "Start recording", busy: state.starting) {
                                Circle().fill(.white).frame(width: 7, height: 7)
                            }
                        }
                        .buttonStyle(ControlStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!state.canStart)
                        .help("Start recording now (⌘N)")
                        .transition(.opacity)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : Theme.feedback, value: recording)
    }
}

/// Content that shows the recording time. Only this observes the clock, so its tick redraws the time, not the window.
struct ElapsedReader<Content: View>: View {
    @ObservedObject var clock: ElapsedClock
    @ViewBuilder let content: (Double) -> Content
    var body: some View { content(clock.seconds) }
}

/// Record button content: a glyph, replaced by dot progress while the action runs.
struct RecordLabel<Glyph: View>: View {
    let title: String
    let busy: Bool
    @ViewBuilder let glyph: Glyph
    var body: some View {
        HStack(spacing: 8) {
            if busy { DotProgress(value: nil, dots: 4, color: .white).frame(width: 22, height: 5) } else { glyph }
            Text(title)
        }
    }
}

/// Compact meeting row with live state, for the menu-bar panel and the library sidebar.
struct MeetingRow: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        // The title gets the full width and two lines, since AI titles carry the meeting's topic; the duration
        // sits at the end of the metadata line, so durations still read as one column down the list.
        VStack(alignment: .leading, spacing: 5) {
            Text(meeting.title).font(.system(size: 13, weight: .medium)).lineSpacing(1)
                .lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: meeting.title)
                .help(meeting.title)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                status
                Spacer(minLength: 4)
                Group {
                    if meeting.id == state.activeID {
                        ElapsedReader(clock: state.clock) { Text(Meeting.timestamp($0)) }
                    } else {
                        Text(Meeting.timestamp(meeting.keptDuration))
                    }
                }
                .font(Theme.mono).secondaryText().monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 4).padding(.vertical, 4)
        .background(Theme.orange.opacity(state.renamedID == meeting.id ? 0.09 : 0), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .padding(.horizontal, -4).padding(.vertical, -4)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.4), value: state.renamedID)
    }
    @ViewBuilder var status: some View {
            if meeting.id == state.processingID {
                HStack(spacing: 8) {
                    DotProgress(value: state.engine.fraction, dots: 24).frame(width: 120, height: 5)
                    MonoLabel("\(Int(state.engine.fraction * 100))%", color: Theme.orangeText)
                }
                .frame(height: 13)
            } else {
                HStack(spacing: 6) {
                    if state.renamedID == meeting.id {
                        Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.orange)
                        MonoLabel("Renamed by AI", color: Theme.orangeText)
                    } else if let activity {
                        Circle().fill(Theme.orange).frame(width: 5, height: 5)
                        MonoLabel(activity, color: Theme.orangeText)
                    } else {
                        MonoLabel(meeting.createdAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                        if !meeting.summary.isEmpty { Image(systemName: "sparkles").font(.system(size: 9)).foregroundStyle(Theme.orange).accessibilityLabel("Analyzed") }
                        if meeting.status == .failed { Image(systemName: "exclamationmark.circle").font(.system(size: 9)).foregroundStyle(Theme.colleagues).accessibilityLabel("Needs attention") }
                    }
                }
            }
    }
    var activity: String? {
        if meeting.id == state.activeID { return state.recorder.paused ? "Paused" : "Recording" }
        if state.queued.contains(meeting.id) { return "Waiting to transcribe" }
        if meeting.id == state.analyzingID { return "Analyzing" }
        if meeting.id == state.pendingID { return "Preparing" }
        if state.versus?.meetingID == meeting.id && state.versus?.isRunning == true { return "Comparing models" }
        return nil
    }
}

/// Who gets recorded: You (microphone) and Colleagues (Mac audio). Refuses, with a shake, to turn both off.
struct SourcePicker: View {
    @ObservedObject var state: AppState
    @StateObject private var devices = InputDevices()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var refused: CGFloat = 0
    var body: some View {
        HStack(spacing: 8) {
            SourcePill(title: "You", detail: devices.recording(preferred: state.preferences.microphone)?.name ?? "Microphone", symbol: "mic.fill", color: Theme.you, isOn: binding(microphone: true))
            SourcePill(title: "Colleagues", detail: "Mac audio", symbol: "speaker.wave.2.fill", color: Theme.colleagues, isOn: binding(microphone: false))
        }
        .modifier(Shake(animatableData: reduceMotion ? 0 : refused))
        .modifier(FollowsDevices(devices: devices))
    }
    func binding(microphone: Bool) -> Binding<Bool> {
        let source = state.preferences.source
        return Binding(
            get: { microphone ? source.usesMicrophone : source.usesSystemAudio },
            set: { value in
                let next = microphone ? AudioSource.from(microphone: value, system: source.usesSystemAudio) : AudioSource.from(microphone: source.usesMicrophone, system: value)
                guard let next else {
                    if reduceMotion { refused += 1 } else { withAnimation(.linear(duration: 0.35)) { refused += 1 } }
                    return
                }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var body: some View {
        Button {
            if reduceMotion { isOn.toggle() } else { withAnimation(Theme.feedback) { isOn.toggle() } }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isOn ? .white : Theme.secondary)
                    .frame(width: 18, height: 18)
                    .background(isOn ? color : Theme.line, in: Circle())
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(isOn ? Color.primary : Theme.secondary)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                SwitchKnob(isOn: isOn, color: color)
            }
            .padding(.leading, 6).padding(.trailing, 8)
            .frame(maxWidth: .infinity, minHeight: Theme.controlHeight)
            .background(isOn ? color.opacity(0.08) : hovering ? Theme.line.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(isOn ? color.opacity(hovering ? 0.5 : 0.28) : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
        .help(isOn ? "\(title) (\(detail)) will be recorded. Click to turn off." : "Click to record \(title.lowercased()) (\(detail)).")
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(isOn ? "Recorded" : "Not recorded")
        .accessibilityAddTraits(.isToggle)
    }
}

/// The connected microphones, kept current by Core Audio while a view that shows them is on screen: connecting or
/// removing one, or changing the default input, refreshes the list.
@MainActor
final class InputDevices: ObservableObject {
    @Published private(set) var inputs: [AudioDevice] = []
    @Published private(set) var defaultID: AudioObjectID?
    /// Input channels by device UID, read with the list instead of on every render.
    @Published private(set) var channels: [String: Int] = [:]
    private var listener: AudioObjectPropertyListenerBlock?
    private static let watched = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice]

    /// The microphone that records You: the chosen one while it is connected, otherwise the automatic one.
    func recording(preferred uid: String?) -> AudioDevice? {
        AudioDevice.microphone(preferred: uid, among: inputs, defaultID: defaultID)
    }
    func start() {
        refresh()
        guard listener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
        for selector in Self.watched {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = listener
    }
    func stop() {
        guard let listener else { return }
        for selector in Self.watched {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        self.listener = nil
    }
    private func refresh() {
        inputs = AudioDevice.inputs()
        defaultID = AudioDevice.defaultDevice(input: true)
        channels = Dictionary(inputs.map { ($0.uid, $0.channelCount) }) { first, _ in first }
    }
    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}

struct FollowsDevices: ViewModifier {
    let devices: InputDevices
    @Environment(\.offscreen) private var offscreen
    func body(content: Content) -> some View {
        content
            .onAppear { if !offscreen { devices.start() } }
            .onChange(of: offscreen) { _, hidden in if hidden { devices.stop() } else { devices.start() } }
            .onDisappear { devices.stop() }
    }
}

