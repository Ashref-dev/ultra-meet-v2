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
    private var microphone: AudioCapture?
    private var system: AudioCapture?
    private var meter: Timer?
    private var clock: RecordingClock?
    private var captureID = UUID()
    var duration: Double { clock?.elapsed() ?? 0 }
    private(set) var captureFailure: String?
    var onError: ((String) -> Void)?

    /// Records the chosen sides into `folder`, both from one shared start so You and Colleagues line up. Returns the
    /// sides actually recording and, when Mac audio couldn't start, why: the microphone still records, so the
    /// meeting isn't lost to a missing output device or permission.
    func start(folder: URL, source: AudioSource, microphone preferred: String?, channel: Int?) async throws -> (AudioSource, String?) {
        captureFailure = nil
        captureID = UUID()
        let session = captureID
        if source != .system {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw AppError.message("Microphone access is off. Enable Ultra Transcribe in System Settings → Privacy & Security → Microphone, then try again.") }
        }
        try Task.checkCancellation()
        var recording = source
        var warning: String?
        do {
            let started = AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())
            if source != .microphone {
                do { system = try begin(.system, file: folder.appendingPathComponent("system.caf"), started: started, session: session) }
                catch where source == .both {
                    recording = .microphone
                    warning = "Mac audio isn’t being recorded, only your microphone. \(error.localizedDescription)"
                }
            }
            if source != .system { self.microphone = try begin(.microphone(preferred: preferred, channel: channel), file: folder.appendingPathComponent("microphone.caf"), started: started, session: session) }
            paused = false
            clock = RecordingClock()
            levels.reset()
            meter = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.paused, self.captureID == session else { return }
                    let you = self.microphone?.level, colleagues = self.system?.level
                    self.levels.push(.init(you: Self.normalized(you ?? 0), colleagues: Self.normalized(colleagues ?? 0)), interval: 0.08,
                                     silent: ((you ?? 1) < 0.000_01, (colleagues ?? 1) < 0.000_01))
                }
            }
            if let meter { RunLoop.main.add(meter, forMode: .common) }
        } catch { await stop(); throw error }
        return (recording, warning)
    }
    private func begin(_ source: AudioCapture.Source, file: URL, started: Double, session: UUID) throws -> AudioCapture {
        let capture = AudioCapture(source)
        let errorHandler = onError
        capture.onError = { [weak self] message in Task { @MainActor in
            guard self?.captureID == session else { return }
            self?.captureFailure = message
            errorHandler?(message)
        } }
        captures.append(capture)
        try capture.start(url: file, started: started)
        return capture
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
        microphone = nil
        system = nil
        captureID = UUID() // late errors and levels from this recording are ignored
        paused = false
        clock = nil
    }
}
