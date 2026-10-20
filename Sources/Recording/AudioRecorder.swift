import AVFoundation
import Combine

/// Live input levels, published separately so 12 Hz meter updates only redraw the visualizers.
@MainActor
final class LevelMeter: ObservableObject {
    struct Sample: Equatable { var you: Float; var colleagues: Float }
    /// Enough history to fill the widest window: one dot column per sample.
    static let length = 480
    @Published private(set) var history = Array(repeating: Sample(you: 0, colleagues: 0), count: LevelMeter.length)
    @Published private(set) var youSeconds: Double = 0
    @Published private(set) var colleaguesSeconds: Double = 0
    /// Seconds of unbroken digital silence per side: a muted or wrong input, or a call playing elsewhere.
    @Published private(set) var youSilence: Double = 0
    @Published private(set) var colleaguesSilence: Double = 0
    var latest: Sample { history.last ?? Sample(you: 0, colleagues: 0) }
    var youShare: Double? {
        let total = youSeconds + colleaguesSeconds
        return total > 2 ? youSeconds / total : nil
    }
    /// Maps -60…0 dBFS to 0…1 so quiet voices still register visibly.
    static func normalized(decibels: Float) -> Float { max(0, min(1, (decibels + 60) / 60)) }
    func push(_ sample: Sample, interval: Double, silent: (you: Bool, colleagues: Bool) = (false, false)) {
        history.append(sample)
        history.removeFirst(history.count - Self.length)
        if sample.you > 0.33 { youSeconds += interval }
        if sample.colleagues > 0.33 { colleaguesSeconds += interval }
        youSilence = silent.you ? youSilence + interval : 0
        colleaguesSilence = silent.colleagues ? colleaguesSilence + interval : 0
    }
    func reset() {
        history = Array(repeating: Sample(you: 0, colleagues: 0), count: Self.length)
        youSeconds = 0
        colleaguesSeconds = 0
        youSilence = 0
        colleaguesSilence = 0
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published var paused = false
    let levels = LevelMeter()
    private var captures: [AudioCapture] = []
    private var meter: Timer?
    private var clock: RecordingClock?
    private var microphoneLevel: Float = 0
    private var systemLevel: Float = 0
    private var captureID = UUID()
    var duration: Double { clock?.elapsed() ?? 0 }
    private(set) var captureFailure: String?
    var onError: ((String) -> Void)?

    /// Records the chosen sides into `folder`, both from one shared start so You and Colleagues line up.
    func start(folder: URL, source: AudioSource, microphone: String?) async throws {
        captureFailure = nil
        captureID = UUID()
        let session = captureID
        if source != .system {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw AppError.message("Microphone access is off. Enable Ultra Transcribe in System Settings → Privacy & Security → Microphone, then try again.") }
        }
        try Task.checkCancellation()
        do {
            let started = AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())
            if source != .microphone { try begin(.system, file: folder.appendingPathComponent("system.caf"), started: started, session: session) }
            if source != .system { try begin(.microphone(preferred: microphone), file: folder.appendingPathComponent("microphone.caf"), started: started, session: session) }
            paused = false
            clock = RecordingClock()
            levels.reset()
            let recordsMicrophone = source != .system, recordsSystem = source != .microphone
            meter = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.paused else { return }
                    let you = recordsMicrophone ? Self.normalized(self.microphoneLevel) : 0
                    self.levels.push(.init(you: you, colleagues: Self.normalized(self.systemLevel)), interval: 0.08,
                                     silent: (recordsMicrophone && self.microphoneLevel < 0.000_01, recordsSystem && self.systemLevel < 0.000_01))
                }
            }
            if let meter { RunLoop.main.add(meter, forMode: .common) }
        } catch { await stop(); throw error }
    }
    private func begin(_ source: AudioCapture.Source, file: URL, started: Double, session: UUID) throws {
        let capture = AudioCapture(source)
        let errorHandler = onError
        capture.onError = { [weak self] message in Task { @MainActor in
            if self?.captureID == session { self?.captureFailure = message }
            errorHandler?(message)
        } }
        let isSystem = source == .system
        capture.onLevel = { [weak self] value in Task { @MainActor in
            guard self?.captureID == session else { return }
            if isSystem { self?.systemLevel = value } else { self?.microphoneLevel = value }
        } }
        captures.append(capture)
        try capture.start(url: file, started: started)
    }
    private static func normalized(_ rms: Float) -> Float { LevelMeter.normalized(decibels: 20 * log10(max(rms, 0.000_001))) }
    func togglePause() {
        paused.toggle()
        if paused { clock?.pause() } else { clock?.resume() }
        captures.forEach { $0.setPaused(paused) }
    }
    func stop() async {
        meter?.invalidate()
        meter = nil
        captures.forEach { $0.stop() }
        captureFailure = captureFailure ?? captures.lazy.compactMap(\.captureFailure).first
        captures = []
        microphoneLevel = 0
        systemLevel = 0
        paused = false
        clock = nil
    }
}
