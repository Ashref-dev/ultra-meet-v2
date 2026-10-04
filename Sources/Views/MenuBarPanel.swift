import AVFoundation
import SwiftUI

/// The whole recorder, in the menu bar: choose sources, start, watch, jot a note, pause, stop.
struct MenuBarPanel: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var recording: Bool { state.activeID != nil }
    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if let meeting = state.active { LiveCard(state: state, meeting: meeting) } else { ReadyCard(state: state) }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .padding(.horizontal, 10)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            if let error = state.error { banner(error).padding(.horizontal, 10).padding(.top, 8) }
            DotWaveform(meter: state.recorder.levels, live: recording, paused: state.recorder.paused)
                .frame(height: 66)
                .padding(.horizontal, 6)
                .padding(.top, 8)
            RecorderControls(state: state).padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 12)
            if !recording && !recent.isEmpty { recentList }
        }
        .frame(width: 380)
        .background(Theme.background)
        .tint(Theme.orange)
        .animation(reduceMotion ? nil : Theme.selection, value: recording)
        .animation(reduceMotion ? nil : Theme.feedback, value: state.error)
    }
    var header: some View {
        HStack(spacing: 8) {
            LogoMark(size: 12)
            MonoLabel("Ultra Transcribe")
            Spacer()
            if recording {
                HStack(spacing: 5) {
                    Circle().fill(state.recorder.paused ? Theme.secondary : Theme.orange).frame(width: 6, height: 6)
                        .opacity(state.recorder.paused || reduceMotion || pulse ? 1 : 0.35)
                    MonoLabel(state.recorder.paused ? "Paused" : "Rec", color: state.recorder.paused ? Theme.secondary : Theme.orange)
                }
                .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse.toggle() } }
            }
            Menu {
                if recording {
                    Button("Microphone Mode…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }
                    Divider()
                }
                Button("Open Meeting Library") { state.showMeeting(nil) }
                Button("Import Audio…") { state.importAudio() }.disabled(!state.canStart)
                Divider()
                Button("Settings…") { state.showSettings(.general) }
                Divider()
                Button("Quit Ultra Transcribe") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 22).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .focusEffectDisabled()
            .foregroundStyle(Theme.secondary)
            .help("More").accessibilityLabel("More options")
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
    }
    func banner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.orange)
            Text(message).font(.system(size: 11.5)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { state.error = nil } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Dismiss")
        }
        .padding(10)
        .background(Theme.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
    var recent: [Meeting] { Array(state.meetings.prefix(3)) }
    var recentList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider().padding(.bottom, 8)
            HStack {
                MonoLabel("Recent")
                Spacer()
                Button("All meetings") { state.showMeeting(nil) }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
            .padding(.horizontal, 16)
            ForEach(recent) { meeting in
                Button { state.showMeeting(meeting.id) } label: {
                    MeetingRow(state: state, meeting: meeting).padding(.horizontal, 10).padding(.vertical, 8)
                }
                .buttonStyle(RowStyle())
                .padding(.horizontal, 6)
            }
        }
        .padding(.bottom, 10)
    }
}

/// Idle card: who gets recorded, as two balanced tiles.
private struct ReadyCard: View {
    @ObservedObject var state: AppState
    @State private var refused: CGFloat = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready to record").font(.system(size: 19, weight: .semibold)).tracking(-0.4)
                Spacer()
                MonoLabel(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }
            HStack(spacing: 6) {
                SourcePill(title: "You", detail: "Microphone", symbol: "mic.fill", color: Theme.you, isOn: binding(microphone: true))
                SourcePill(title: "Colleagues", detail: "Mac audio", symbol: "speaker.wave.2.fill", color: Theme.colleagues, isOn: binding(microphone: false))
                Spacer(minLength: 0)
            }
            .modifier(Shake(animatableData: refused))
            if !state.engine.ready(state.preferences.model) && !state.engine.busy {
                Button { state.showSettings(.transcription) } label: {
                    Label("Install the speech model to get transcripts", systemImage: "arrow.down.circle").font(.system(size: 11.5))
                }.buttonStyle(.link)
            }
        }
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
private struct SourcePill: View {
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
                Capsule().fill(isOn ? color : Theme.secondary.opacity(0.25)).frame(width: 22, height: 13)
                    .overlay(alignment: isOn ? .trailing : .leading) { Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5) }
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

/// Live card: name, participants, talk share and a quick note.
private struct LiveCard: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                EditableTitle(title: meeting.title, size: 18) { state.rename(meeting.id, to: $0) }
                Spacer(minLength: 4)
                Participants(meter: state.recorder.levels, source: meeting.source)
            }
            MonoLabel("Started \(meeting.createdAt.formatted(.dateTime.hour().minute())) · \(meeting.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
            TalkShare(meter: state.recorder.levels, source: meeting.source)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "pencil").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondary)
                TextField("Jot a note…", text: Binding(get: { meeting.notes }, set: { value in state.update(meeting.id) { $0.notes = value } }), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 12.5)).lineLimit(1...4)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
    }
}

private struct Participants: View {
    @ObservedObject var meter: LevelMeter
    let source: AudioSource
    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: -6) {
                if source.usesMicrophone { SpeakerAvatar(source: "microphone", size: 22, level: meter.latest.you).overlay(Circle().stroke(Theme.paper, lineWidth: 2)) }
                if source.usesSystemAudio { SpeakerAvatar(source: "system", size: 22, level: meter.latest.colleagues).overlay(Circle().stroke(Theme.paper, lineWidth: 2)) }
            }
            MonoLabel(source == .both ? "2 sides" : "1 side")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source == .both ? "Recording you and your colleagues" : source == .microphone ? "Recording you" : "Recording your colleagues")
    }
}

/// Split bar of speaking time: green for you, orange for colleagues.
private struct TalkShare: View {
    @ObservedObject var meter: LevelMeter
    let source: AudioSource
    var body: some View {
        let share = meter.youShare
        VStack(spacing: 6) {
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    if let share {
                        Capsule().fill(Theme.you).frame(width: max(4, (geometry.size.width - 2) * share))
                        Capsule().fill(Theme.colleagues)
                    } else {
                        Capsule().fill(Theme.line)
                    }
                }
            }
            .frame(height: 5)
            .animation(.easeOut(duration: 0.4), value: share)
            HStack {
                MonoLabel(share.map { "You \(Int(($0 * 100).rounded()))%" } ?? (source.usesMicrophone ? "You" : "You · off"), color: Theme.you)
                Spacer()
                MonoLabel("Talk time", color: Theme.secondary.opacity(0.7))
                Spacer()
                MonoLabel(share.map { "\(Int(((1 - $0) * 100).rounded()))% Colleagues" } ?? (source.usesSystemAudio ? "Colleagues" : "Colleagues · off"), color: Theme.colleagues)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Press feedback without chrome, for custom tiles.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1).animation(Theme.feedback, value: configuration.isPressed)
    }
}

/// Hover, press and selected highlight for list rows that behave like buttons.
struct RowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { RowBody(configuration: configuration, selected: selected) }
    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(selected ? Theme.paper : hovering || configuration.isPressed ? Theme.line.opacity(0.7) : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(selected ? Theme.line : .clear))
                .shadow(color: selected ? .black.opacity(0.04) : .clear, radius: 4, y: 1)
                .onHover { hovering = $0 }
                .animation(Theme.feedback, value: hovering)
                .animation(Theme.feedback, value: selected)
        }
    }
}
