import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, recording, transcription, analysis, storage, credits
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "General"
        case .recording: return "Recording"
        case .transcription: return "Transcription"
        case .analysis: return "AI Analysis"
        case .storage: return "Storage"
        case .credits: return "Credits"
        }
    }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .recording: return "mic"
        case .transcription: return "waveform"
        case .analysis: return "sparkles"
        case .storage: return "internaldrive"
        case .credits: return "info.circle"
        }
    }
}
struct AnalysisFailure: Equatable { let id: UUID; let message: String }

@MainActor
final class AppState: ObservableObject {
    @Published var meetings: [Meeting]
    @Published var preferences: Preferences
    @Published var selectedID: UUID?
    @Published var activeID: UUID?
    @Published var processingID: UUID?
    /// The recording being transcribed while it records.
    @Published var liveID: UUID?
    @Published var redoingLineID: UUID?
    @Published var termSuggestion: TermSuggestion?
    @Published var pendingID: UUID?
    @Published var analyzingID: UUID?
    @Published var analysisFailure: AnalysisFailure?
    @Published var renamedID: UUID?
    @Published var settingsPane: SettingsPane = .general
    @Published var queued: [UUID] = []
    @Published var elapsed: Double = 0
    @Published var error: String?
    @Published var search = ""
    @Published var starting = false
    @Published var stopping = false
    let library: MeetingLibrary
    let recorder = AudioRecorder()
    let engine: LocalEngine
    let updater = Updater()
    private var hotKey: GlobalHotKey?
    var recordingTimer: Timer?
    var startupTask: Task<Void, Never>?
    var operationTask: Task<Void, Never>?
    var analysisTask: Task<Void, Never>?
    var preparingToQuit = false
    /// Reads the OpenRouter key; tests replace it so they never touch the real Keychain.
    var readKey: () -> String = Keychain.read
    /// Window routing, provided by the application delegate.
    var showMeeting: (UUID?) -> Void = { _ in }
    var showSettings: (SettingsPane) -> Void = { _ in }
    var showSetup: () -> Void = {}
    private var subscriptions = Set<AnyCancellable>()
    private var retentionTimer: Timer?
    var active: Meeting? { meetings.first { $0.id == activeID } }
    var selected: Meeting? { meetings.first { $0.id == selectedID } }
    var isWorking: Bool { processingID != nil || engine.busy || !queued.isEmpty }
    var canStart: Bool { activeID == nil && !starting && startupTask == nil && !preparingToQuit }
    func isProtected(_ id: UUID) -> Bool { id == activeID || id == processingID || id == liveID || id == pendingID || queued.contains(id) }

    init(root: URL? = nil) throws {
        library = try MeetingLibrary(root: root)
        preferences = try library.loadPreferences()
        let snapshot = try library.snapshot()
        meetings = snapshot.meetings
        error = snapshot.warnings.isEmpty ? nil : snapshot.warnings.joined(separator: "\n\n")
        engine = LocalEngine(root: library.root)
        for index in meetings.indices where [.importing, .recording, .processing].contains(meetings[index].status) {
            meetings[index] = library.recover(meetings[index])
            try library.save(meetings[index])
        }
        selectedID = meetings.first?.id
        recorder.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        engine.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        updater.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        recorder.onError = { [weak self] message in self?.captureFailed(message) }
        try applyRetention()
        retentionTimer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                do { try self.applyRetention() }
                catch { self.error = "Audio retention cleanup failed: \(error.localizedDescription)" }
            }
        }
        if let retentionTimer { RunLoop.main.add(retentionTimer, forMode: .common) }
    }
    deinit { retentionTimer?.invalidate() }
    func update(_ id: UUID, change: (inout Meeting) -> Void) {
        guard let index = meetings.firstIndex(where: { $0.id == id }) else { return }
        change(&meetings[index])
        do { try library.save(meetings[index]) } catch { self.error = "Could not save this meeting: \(error.localizedDescription)" }
    }
    func rename(_ id: UUID, to title: String) {
        update(id) { $0.title = title; $0.titleEdited = true }
    }
    func savePreferences() {
        do {
            try library.savePreferences(preferences)
            try applyRetention()
            if let app = NSApp {
                app.appearance = preferences.appearance == "light" ? NSAppearance(named: .aqua) : preferences.appearance == "dark" ? NSAppearance(named: .darkAqua) : nil
            }
            applyGlobalShortcut()
        } catch { self.error = error.localizedDescription }
    }
    /// Control-Option-Command-R toggles recording from any app. Registered only in the running app, never in tests.
    func applyGlobalShortcut() {
        guard Notifier.available else { return }
        if preferences.globalShortcut, hotKey == nil {
            hotKey = GlobalHotKey { [weak self] in
                guard let self else { return }
                if self.activeID != nil { self.stopRecording() } else { self.startRecording() }
            }
        } else if !preferences.globalShortcut {
            hotKey = nil
        }
    }
    func saveOpenRouterKey(_ key: String) throws {
        try Keychain.save(key)
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
            savePreferences()
        } catch { self.error = "Could not change launch at login: \(error.localizedDescription)" }
    }
    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        preferences.launchAtLogin = status == .enabled || status == .requiresApproval
    }
    func applyRetention() throws {
        for index in meetings.indices where !isProtected(meetings[index].id) && meetings[index].audioExpired(after: preferences.retentionDays, now: Date()) {
            try library.removeAudio(meetings[index].id)
            meetings[index].audioDeleted = true
            try library.save(meetings[index])
        }
    }
    func deleteMeeting(_ id: UUID) {
        guard !isProtected(id) else { return }
        do {
            try FileManager.default.trashItem(at: library.folder(id), resultingItemURL: nil)
            meetings.removeAll { $0.id == id }
            if selectedID == id { selectedID = meetings.first?.id }
        } catch { self.error = error.localizedDescription }
    }
    func deleteAudio(_ id: UUID) {
        guard !isProtected(id) else { return }
        do { try library.removeAudio(id); update(id) { $0.audioDeleted = true } }
        catch { self.error = error.localizedDescription }
    }
    func export(_ meeting: Meeting) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = meeting.title.replacingOccurrences(of: "/", with: "-") + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try meeting.markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = error.localizedDescription }
    }
    func importAudio() {
        guard canStart else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var meeting = Meeting(title: url.deletingPathExtension().lastPathComponent)
            meeting.model = preferences.model
            meeting.source = .microphone
            meeting.status = .importing
            meeting.titleEdited = false
            try library.save(meeting)
            meetings.insert(meeting, at: 0)
            selectedID = meeting.id
            starting = true
            pendingID = meeting.id
            let destination = library.folder(meeting.id).appendingPathComponent("imported.wav")
            startupTask = Task {
                defer { pendingID = nil; starting = false; startupTask = nil }
                do {
                    let conversion = Task.detached(priority: .userInitiated) { try AudioImport.convert(source: url, destination: destination) }
                    let duration = try await withTaskCancellationHandler(operation: { try await conversion.value }, onCancel: { conversion.cancel() })
                    update(meeting.id) { $0.duration = duration; $0.status = .interrupted }
                    try Task.checkCancellation()
                    if !preparingToQuit { transcribe(meeting.id) }
                } catch is CancellationError {
                    update(meeting.id) {
                        if $0.status == .importing { $0.captureError = "Audio import did not finish." }
                        $0.status = .interrupted
                        $0.error = "Import cancelled. Retained audio remains on this Mac."
                    }
                } catch {
                    update(meeting.id) { $0.status = .failed; $0.captureError = "Audio import did not finish."; $0.error = error.localizedDescription }
                    self.error = "Could not import audio: \(error.localizedDescription)"
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}
