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
            .padding(.horizontal, 12)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            if let error = state.error {
                InlineHint(symbol: "exclamationmark.circle.fill", text: error, dismiss: { state.error = nil })
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            if let release = state.updater.available, !recording {
                InlineHint(symbol: "arrow.down.circle", text: "Ultra Transcribe \(release.version?.description ?? release.tag) is available.", action: ("Update", { state.showSettings(.credits) }))
                    .padding(.horizontal, 12).padding(.top, 8)
            }
            DotWaveform(meter: state.recorder.levels, live: recording, paused: state.recorder.paused)
                .frame(height: 64)
                .padding(.horizontal, 12)
                .padding(.top, 12)
            RecorderControls(state: state).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 16)
            if !recording && !recent.isEmpty { recentList }
        }
        .frame(width: 380)
        .popoverSurface()
        .animation(reduceMotion ? nil : Theme.selection, value: recording)
        .animation(reduceMotion ? nil : Theme.feedback, value: state.error)
    }
    var header: some View {
        HStack(spacing: 8) {
            LogoMark(size: 13)
            Text("Ultra Transcribe").font(.system(size: 13, weight: .semibold))
            Spacer()
            if recording {
                HStack(spacing: 6) {
                    Circle().fill(state.recorder.paused ? Theme.secondary : Theme.orange).frame(width: 6, height: 6)
                        .opacity(state.recorder.paused || reduceMotion || pulse ? 1 : 0.35)
                    MonoLabel(state.recorder.paused ? "Paused" : "Rec", color: state.recorder.paused ? Theme.secondary : Theme.orange)
                }
                .onAppear {
                    guard !reduceMotion else { pulse = true; return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse.toggle() }
                }
            }
            MoreMenu(label: "More options") {
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
            }
        }
        .padding(.leading, 16).padding(.trailing, 12).padding(.vertical, 12)
    }
    var recent: [Meeting] { Array(state.meetings.prefix(3)) }
    var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().padding(.bottom, 8)
            HStack {
                MonoLabel("Recent")
                Spacer()
                Button { state.showMeeting(nil) } label: { LinkLabel("All meetings") }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
            .padding(.leading, 16).padding(.trailing, 8)
            ForEach(recent) { meeting in
                Button { state.showMeeting(meeting.id) } label: {
                    MeetingRow(state: state, meeting: meeting).padding(.horizontal, 8).padding(.vertical, 8)
                }
                .buttonStyle(RowStyle())
                .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }
}

/// Idle card: title, date and who gets recorded.
private struct ReadyCard: View {
    @ObservedObject var state: AppState
    /// `LocalEngine.ready` reads files, so it is checked on open and when an install starts or ends, not every render.
    @State private var modelMissing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ready to record").font(.system(size: 18, weight: .semibold)).tracking(-0.4)
                Spacer()
                MonoLabel(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }
            SourcePicker(state: state)
            if modelMissing && !state.engine.busy {
                Button { state.showSettings(.transcription) } label: {
                    Label("Install the speech model to get transcripts", systemImage: "arrow.down.circle").font(.system(size: 11.5))
                }
                .buttonStyle(PressStyle()).foregroundStyle(Theme.orange)
            }
        }
        .onAppear(perform: checkModel)
        .onChange(of: state.engine.busy) { _, _ in checkModel() }
        .onChange(of: state.preferences.model) { _, _ in checkModel() }
    }
    func checkModel() { modelMissing = !state.engine.ready(state.preferences.model) }
}

/// Live card: name, participants, talk share and a quick note.
private struct LiveCard: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    @Environment(\.offscreen) private var offscreen
    var body: some View {
        let meter = offscreen ? LevelMeter.still : state.recorder.levels
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                EditableTitle(title: meeting.title, size: 18) { state.rename(meeting.id, to: $0) }
                Spacer(minLength: 4)
                Participants(meter: meter, source: meeting.source)
            }
            MonoLabel("Started \(meeting.createdAt.formatted(.dateTime.hour().minute())) · \(meeting.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
            TalkShare(meter: meter, source: meeting.source)
            HealthHints(meter: meter, source: meeting.source)
            if state.liveID == meeting.id { LiveLines(lines: state.engine.partial) }
            NoteEditor(text: Binding(get: { meeting.notes }, set: { value in state.update(meeting.id) { $0.notes = value } }), placeholder: "Jot a note…")
                .frame(height: 96)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: share)
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

/// The last lines of the live transcript, newest at the bottom.
private struct LiveLines: View {
    let lines: [TranscriptSegment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoLabel("Live transcript", color: Theme.secondary.opacity(0.8))
            if lines.isEmpty {
                Text("Lines appear as people finish sentences.").font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            ForEach(lines.suffix(3)) { line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Theme.speakerColor(line.source)).frame(width: 6, height: 6).accessibilityLabel(line.speaker)
                    Text(line.text).font(.system(size: 12)).lineLimit(2)
                        .foregroundStyle(line.isUncertain ? Theme.secondary : Color.primary)
                        .multilineTextAlignment(line.isRightToLeft ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: line.isRightToLeft ? .trailing : .leading)
                }
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.selection, value: lines.count)
    }
}

/// Warnings that catch a muted microphone or a call playing on another device while there is time to fix it.
private struct HealthHints: View {
    @ObservedObject var meter: LevelMeter
    let source: AudioSource
    var body: some View {
        if source.usesMicrophone && meter.youSilence >= 10 {
            InlineHint(symbol: "mic.slash", text: "Your microphone isn’t picking up any sound.", action: ("Sound…", { openSound() }))
        } else if source.usesSystemAudio && meter.colleaguesSilence >= 60 {
            InlineHint(symbol: "speaker.slash", text: "No sound from your Mac for a minute. If you’re on a call, check that it plays on this Mac.")
        }
    }
    func openSound() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
