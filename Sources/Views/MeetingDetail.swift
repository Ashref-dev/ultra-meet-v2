import AppKit
import SwiftUI

struct MeetingDetail: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    @State private var tab = "Transcript"
    @State private var deleteAudioConfirmation = false
    @StateObject private var playback = AudioPlayback()
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isActive: Bool { meeting.id == state.activeID }
    var isTranscribing: Bool { meeting.id == state.processingID || meeting.id == state.pendingID || state.queued.contains(meeting.id) }
    var isAnalyzing: Bool { meeting.id == state.analyzingID }
    static let tabs = [TabItem(id: "Transcript", symbol: "waveform"), TabItem(id: "AI notes", symbol: "sparkles"), TabItem(id: "My notes", symbol: "pencil")]
    var body: some View {
        VStack(spacing: 0) {
            header
            TabStrip(tabs: Self.tabs, selection: $tab).padding(.horizontal, 22)
            Divider()
            if let error = meeting.error, !isActive { notice(error) }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab)
                .transition(.opacity.animation(.easeOut(duration: 0.14)))
            if playback.duration > 0 { player }
            if isActive {
                VStack(spacing: 0) {
                    Divider()
                    DotWaveform(meter: state.recorder.levels, live: true, paused: state.recorder.paused).frame(height: 50).padding(.horizontal, 20).padding(.top, 10)
                    RecorderControls(state: state).padding(.horizontal, 28).padding(.vertical, 12)
                }.background(Theme.background)
            }
        }
        .background(Theme.paper)
        .onChange(of: meeting.id) { _, _ in playback.stop(); copied = false; tab = "Transcript" }
        .onChange(of: tab) { _, _ in copied = false }
        .onChange(of: state.activeID) { _, id in if id != nil { playback.stop() } }
        .onChange(of: meeting.audioDeleted) { _, deleted in if deleted { playback.stop() } }
        .onDisappear { playback.stop() }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(1.6))
            copied = false
        }
        .confirmationDialog("Permanently delete this meeting’s audio?", isPresented: $deleteAudioConfirmation) {
            Button("Delete Audio", role: .destructive) { playback.stop(); state.deleteAudio(meeting.id) }
        } message: { Text("The transcript and notes stay. You won’t be able to play or transcribe the recording again.") }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusBadge(meeting: meeting)
                Spacer()
                Button { copyContent() } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").contentTransition(.symbolEffect(.replace)) }
                    .buttonStyle(ControlStyle(compact: true)).animation(reduceMotion ? nil : Theme.feedback, value: copied)
                    .help("Copy the \(tab.lowercased())")
                Button { state.export(meeting) } label: { Label("Export", systemImage: "square.and.arrow.up") }
                    .buttonStyle(ControlStyle(compact: true)).help("Export everything as Markdown")
                actions
            }
            EditableTitle(title: meeting.title, size: 26) { state.rename(meeting.id, to: $0) }
                .padding(.top, 8)
            HStack(spacing: 14) {
                MonoLabel(meeting.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute()))
                MonoLabel(Meeting.timestamp(isActive ? state.elapsed : meeting.duration))
                Spacer()
                if !speakers.isEmpty {
                    HStack(spacing: 8) {
                        HStack(spacing: -6) { ForEach(speakers, id: \.self) { SpeakerAvatar(source: $0, size: 20).overlay(Circle().stroke(Theme.paper, lineWidth: 2)) } }
                        MonoLabel(speakers.map { $0 == "system" ? "Colleagues" : $0 == "microphone" ? "You" : "Speaker" }.joined(separator: " · "))
                    }
                }
            }
        }
        .padding(.horizontal, 32).padding(.top, 26).padding(.bottom, 14)
    }
    var speakers: [String] {
        let sources = Set(meeting.segments.map(\.source))
        return ["microphone", "system", "imported"].filter(sources.contains)
    }
    var actions: some View {
        Menu {
            Button("Analyze with AI") { tab = "AI notes"; state.analyze(meeting.id) }.disabled(meeting.segments.isEmpty || state.analyzingID != nil)
            Button("Transcribe Again") { state.transcribe(meeting.id) }.disabled(isActive || isTranscribing || meeting.audioDeleted)
            Divider()
            ForEach(audioFiles, id: \.self) { url in
                Button("Play \(label(for: url))") { play(url) }
            }.disabled(isActive)
            Button("Show in Finder") { NSWorkspace.shared.open(state.library.folder(meeting.id)) }
            Divider()
            Button("Delete Audio…", role: .destructive) { deleteAudioConfirmation = true }.disabled(isActive || isTranscribing || meeting.audioDeleted)
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 30, height: 26).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(ControlStyle(compact: true)).menuIndicator(.hidden).fixedSize()
        .help("More actions").accessibilityLabel("More actions")
    }
    func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Theme.orange)
            Text(message).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if !meeting.audioDeleted && !isTranscribing && meeting.segments.isEmpty {
                Button("Transcribe Again") { state.transcribe(meeting.id) }.buttonStyle(ControlStyle(compact: true))
            }
        }
        .padding(.horizontal, 32).padding(.vertical, 12).background(Theme.orange.opacity(0.06))
    }

    // MARK: Content

    @ViewBuilder var content: some View {
        switch tab {
        case "My notes":
            NoteEditor(text: Binding(get: { meeting.notes }, set: { value in state.update(meeting.id) { $0.notes = value } }), placeholder: "Anything worth remembering…", fontSize: 14, inset: CGSize(width: 27, height: 24), fade: 22, framed: false)
        case "AI notes":
            AnalysisView(state: state, meeting: meeting)
        default:
            transcript
        }
    }
    @ViewBuilder var transcript: some View {
        if !meeting.segments.isEmpty {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(SpeakerBlock.group(meeting.segments)) { block in
                        SpeakerBlockView(block: block, canSeek: !meeting.audioDeleted && !isActive) { seek($0) }
                    }
                }
                .padding(.horizontal, 32).padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            placeholder
        }
    }
    var placeholder: some View {
        VStack(spacing: 12) {
            if isTranscribing {
                DotProgress(value: meeting.id == state.processingID ? state.engine.fraction : nil).frame(width: 240, height: 7)
                Text(meeting.id == state.processingID ? state.engine.message : "Waiting for the previous meeting to finish…").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                Button("Cancel") { state.cancelProcessing() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            } else if isActive {
                Text("Listening.").font(.system(size: 18, weight: .medium))
                Text("Your transcript appears when you stop.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            } else {
                Text(meeting.status == .ready ? "No speech was detected." : "No transcript yet.").font(.system(size: 18, weight: .medium))
                if !meeting.audioDeleted {
                    Button("Transcribe") { state.transcribe(meeting.id) }.buttonStyle(ControlStyle()).padding(.top, 4)
                }
            }
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    var player: some View {
        HStack(spacing: 12) {
            Button { playback.togglePause() } label: { Image(systemName: playback.playing ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace)) }
                .buttonStyle(.plain).accessibilityLabel(playback.playing ? "Pause playback" : "Resume playback")
            MonoLabel(playbackTitle)
            Text(Meeting.timestamp(playback.position)).font(Theme.mono).monospacedDigit()
            Slider(value: Binding(get: { playback.position }, set: { playback.seek($0) }), in: 0...max(1, playback.duration)).tint(Theme.orange).controlSize(.small).accessibilityLabel("Playback position")
            Text(Meeting.timestamp(playback.duration)).font(Theme.mono).foregroundStyle(Theme.secondary)
            Button { playback.stop() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Stop playback")
        }
        .padding(.horizontal, 32).padding(.vertical, 12).background(Theme.background)
    }
    @State private var playbackTitle = ""

    // MARK: Audio

    var audioFiles: [URL] {
        guard !meeting.audioDeleted else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: state.library.folder(meeting.id), includingPropertiesForKeys: nil)) ?? [])
            .filter { ["wav", "caf", "m4a", "mp3", "flac", "aiff", "ogg"].contains($0.pathExtension.lowercased()) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func label(for url: URL) -> String {
        switch url.deletingPathExtension().lastPathComponent {
        case "microphone": return "You"
        case "system": return "Colleagues"
        default: return "Recording"
        }
    }
    func seek(_ segment: TranscriptSegment) {
        if let audio = audioFiles.first(where: { $0.deletingPathExtension().lastPathComponent == segment.source }) { play(audio, at: segment.start) }
    }
    func play(_ url: URL, at seconds: Double = 0) {
        do { try playback.play(url, at: seconds); playbackTitle = label(for: url) }
        catch { state.error = "This recording could not be played: \(error.localizedDescription)" }
    }
    func copyContent() {
        let content = tab == "Transcript" ? meeting.transcript : tab == "My notes" ? meeting.notes : meeting.shareableNotes
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
    }
}

/// AI notes tab: call to action, loading, failure and the generated notes.
struct AnalysisView: View {
    @ObservedObject var state: AppState
    let meeting: Meeting
    var analyzing: Bool { state.analyzingID == meeting.id }
    var failure: String? { state.analysisFailure?.id == meeting.id ? state.analysisFailure?.message : nil }
    var body: some View {
        if analyzing {
            VStack(spacing: 14) {
                DotProgress(value: nil, dots: 20).frame(width: 140, height: 6)
                Text("Analyzing the conversation…").font(.system(size: 15, weight: .medium))
                MonoLabel("\(state.preferences.template.name) · \(state.preferences.openRouterModel)")
                Button("Cancel") { state.cancelAnalysis() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if meeting.summary.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "sparkles").font(.system(size: 24, weight: .light)).foregroundStyle(Theme.orange)
                Text("Turn this conversation into notes").font(.system(size: 18, weight: .semibold))
                Text("Summary, decisions, and action items for you and your colleagues.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                if let failure { failureView(failure) }
                HStack(spacing: 8) {
                    TemplatePicker(state: state)
                    analyzeButton
                }.padding(.top, 4)
                MonoLabel("Sends the transcript text to OpenRouter · never audio")
            }
            .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 8) {
                        MonoLabel([meeting.analysisTemplate, meeting.analysisModel.map { $0.components(separatedBy: "/").last ?? $0 }, meeting.analyzedAt?.formatted(.dateTime.day().month(.abbreviated).hour().minute())].compactMap { $0 }.joined(separator: " · "))
                        Spacer()
                        TemplatePicker(state: state)
                        Button { state.analyze(meeting.id) } label: { Label("Re-analyze", systemImage: "arrow.clockwise") }
                            .buttonStyle(ControlStyle(compact: true)).disabled(state.analyzingID != nil || meeting.segments.isEmpty)
                    }
                    if let failure { failureView(failure) }
                    if meeting.notesStale == true {
                        Label("The transcript changed since this analysis. Re-analyze to update.", systemImage: "clock.arrow.circlepath").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    MarkdownNotes(text: meeting.summary).frame(maxWidth: Theme.readingWidth, alignment: .leading)
                }
                .padding(.horizontal, 32).padding(.vertical, 22).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    var analyzeButton: some View {
        Button { state.analyze(meeting.id) } label: { Label("Analyze with AI", systemImage: "sparkles") }
            .buttonStyle(ControlStyle(kind: .primary))
            .disabled(meeting.segments.isEmpty || state.analyzingID != nil)
            .help(meeting.segments.isEmpty ? "Transcribe the meeting first" : "Analyze with \(state.preferences.openRouterModel)")
    }
    func failureView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.orange)
            Text(message).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if message.contains("Settings") {
                Button("Open Settings") { state.showSettings(.analysis) }.buttonStyle(ControlStyle(compact: true))
            }
        }
        .padding(12).frame(maxWidth: 460, alignment: .leading)
        .background(Theme.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// Persistent analysis template selection.
struct TemplatePicker: View {
    @ObservedObject var state: AppState
    var body: some View {
        Menu {
            ForEach(state.preferences.templates) { template in
                Button { state.preferences.templateID = template.id; state.savePreferences() } label: {
                    if template.id == state.preferences.template.id { Label(template.name, systemImage: "checkmark") } else { Text(template.name) }
                }
            }
            Divider()
            Button("Edit Templates…") { state.showSettings(.analysis) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.badge.star").font(.system(size: 10))
                Text(state.preferences.template.name)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
            }
        }
        .menuStyle(.button).buttonStyle(ControlStyle(compact: true)).menuIndicator(.hidden).fixedSize()
        .help("Analysis template")
    }
}
