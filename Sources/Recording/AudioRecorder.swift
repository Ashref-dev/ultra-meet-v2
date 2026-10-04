import AppKit
import AVFoundation

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
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var paused = false
    let levels = LevelMeter()
    private var microphone: AVAudioRecorder?
    private var systemAudio: SystemAudioTap?
    private var meter: Timer?
    private var clock: RecordingClock?
    private var systemLevel: Float = 0
    private var captureID = UUID()
    var duration: Double { clock?.elapsed() ?? 0 }
    private(set) var captureFailure: String?
    var onError: ((String) -> Void)?

    func start(folder: URL, source: AudioSource) async throws {
        captureFailure = nil
        microphone = nil
        captureID = UUID()
        let session = captureID
        if source != .system {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            guard allowed else { throw AppError.message("Microphone access is off. Enable Ultra Transcribe in System Settings → Privacy & Security → Microphone, then try again.") }
        }
        try Task.checkCancellation()
        do {
            if source != .microphone {
                let output = SystemAudioTap()
                let errorHandler = onError
                output.onError = { [weak self] message in Task { @MainActor in
                    if self?.captureID == session { self?.captureFailure = message }
                    errorHandler?(message)
                } }
                output.onLevel = { [weak self] value in Task { @MainActor in
                    if self?.captureID == session { self?.systemLevel = value }
                } }
                systemAudio = output
                try output.start(url: folder.appendingPathComponent("system.caf"))
            }
            if source != .system {
                microphone = try AVAudioRecorder(url: folder.appendingPathComponent("microphone.wav"), settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
                microphone?.isMeteringEnabled = true
                microphone?.delegate = self
                guard microphone?.record() == true else { throw AppError.message("The microphone could not start. Check your input device in System Settings → Sound.") }
            }
            paused = false
            clock = RecordingClock()
            levels.reset()
            meter = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.paused else { return }
                    self.microphone?.updateMeters()
                    let power = self.microphone?.averagePower(forChannel: 0) ?? 0
                    let you = self.microphone == nil ? 0 : LevelMeter.normalized(decibels: power)
                    let colleagues = LevelMeter.normalized(decibels: 20 * log10(max(self.systemLevel, 0.000_001)))
                    self.levels.push(.init(you: you, colleagues: colleagues), interval: 0.08, silent: (self.microphone != nil && power <= -100, self.systemAudio != nil && self.systemLevel < 0.000_01))
                }
            }
            if let meter { RunLoop.main.add(meter, forMode: .common) }
        } catch { await stop(); throw error }
    }
    func togglePause() {
        paused.toggle()
        if paused { clock?.pause() } else { clock?.resume() }
        systemAudio?.setPaused(paused)
        if paused { microphone?.pause() }
        else if let microphone, !microphone.record() { onError?("The microphone could not resume. Check your input device.") }
    }
    func stop() async {
        meter?.invalidate()
        meter = nil
        microphone?.stop()
        systemAudio?.stop()
        captureFailure = captureFailure ?? systemAudio?.captureFailure
        systemAudio = nil
        systemLevel = 0
        paused = false
        clock = nil
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let message = error?.localizedDescription ?? "The microphone recording could not be written."
        Task { @MainActor in
            self.microphoneFailed(recorder, message: message)
        }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag { Task { @MainActor in
            self.microphoneFailed(recorder, message: "The microphone recording ended unexpectedly.")
        } }
    }
    func microphoneFailed(_ recorder: AVAudioRecorder, message: String) {
        guard microphone === recorder else { return }
        captureFailure = message
        onError?(message)
    }
}
