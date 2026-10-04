import Accelerate
import AVFoundation
import Combine

/// Plays a meeting's tracks together, in sync, at an adjustable speed. Tracks start at the same moment of the
/// recording, so one shared start keeps You and Colleagues aligned. Each track is brought to a comfortable level
/// (quiet laptop microphones are often 20 dB below call audio) and a limiter keeps the mix from clipping. Recordings
/// on disk are never changed.
@MainActor
final class AudioPlayback: ObservableObject {
    static let rates: [Float] = [1, 1.25, 1.5, 2]
    /// The playhead, published on its own so ten updates a second redraw the player, not the whole transcript.
    final class Clock: ObservableObject { @Published var position: Double = 0 }
    let clock = Clock()
    @Published private(set) var playing = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var rate: Float = 1
    /// Track names playing, such as "microphone" and "system".
    @Published private(set) var sources: [String] = []
    var position: Double { clock.position }

    private struct Track { let file: AVAudioFile; let player: AVAudioPlayerNode; let gain: AVAudioUnitEQ }
    private let engine = AVAudioEngine()
    private let mix = AVAudioMixerNode()
    private let speed = AVAudioUnitTimePitch()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private var tracks: [Track] = []
    /// Where the current run of the players began, in seconds of the recording.
    private var origin: Double = 0
    /// Bumped whenever the players are rescheduled, so callbacks from an older run are ignored.
    private var run = 0
    private var remaining = 0
    private var timer: Timer?

    init() {
        [mix, speed, limiter].forEach(engine.attach)
        engine.connect(mix, to: speed, format: nil)
        engine.connect(speed, to: limiter, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: nil)
    }

    func play(_ urls: [URL], at seconds: Double = 0) throws {
        stop()
        if let missing = urls.first(where: { !FileManager.default.fileExists(atPath: $0.path) }) {
            throw AppError.message("The audio file \(missing.lastPathComponent) is no longer in this meeting’s folder.")
        }
        for url in urls {
            let file = try AVAudioFile(forReading: url)
            let track = Track(file: file, player: AVAudioPlayerNode(), gain: AVAudioUnitEQ(numberOfBands: 0))
            engine.attach(track.player)
            engine.attach(track.gain)
            engine.connect(track.player, to: track.gain, format: file.processingFormat)
            engine.connect(track.gain, to: mix, fromBus: 0, toBus: mix.nextAvailableInputBus, format: file.processingFormat)
            tracks.append(track)
            Task { track.gain.globalGain = await Task.detached(priority: .userInitiated) { Self.comfortableGain(url) }.value }
        }
        speed.rate = rate
        sources = urls.map { $0.deletingPathExtension().lastPathComponent }
        duration = tracks.map { Double($0.file.length) / $0.file.processingFormat.sampleRate }.max() ?? 0
        do { try engine.start() }
        catch { stop(); throw AppError.message("Audio output could not start: \(error.localizedDescription)") }
        guard schedule(at: seconds) else {
            stop()
            throw AppError.message("This recording has no audio to play.")
        }
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    /// Starts every track that still has audio at `seconds`, together, a moment from now.
    @discardableResult
    private func schedule(at seconds: Double) -> Bool {
        run += 1
        let current = run
        tracks.forEach { $0.player.stop() }
        origin = max(0, min(seconds, duration))
        remaining = 0
        let start = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03))
        for track in tracks {
            let first = AVAudioFramePosition(origin * track.file.processingFormat.sampleRate)
            guard first < track.file.length else { continue }
            remaining += 1
            track.player.scheduleSegment(track.file, startingFrame: first, frameCount: AVAudioFrameCount(track.file.length - first), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finished(current) }
            }
            track.player.play(at: start)
        }
        clock.position = origin
        playing = remaining > 0
        return playing
    }
    private func finished(_ finishedRun: Int) {
        guard finishedRun == run else { return }
        remaining -= 1
        guard remaining <= 0 else { return }
        run += 1
        playing = false
        clock.position = duration
    }
    private func tick() {
        guard playing else { return }
        if !engine.isRunning { pause(); return }
        clock.position = min(duration, currentPosition)
    }
    /// The furthest any track has played, from the players' own render clocks.
    private var currentPosition: Double {
        tracks.compactMap { track -> Double? in
            guard let now = track.player.lastRenderTime, let time = track.player.playerTime(forNodeTime: now) else { return nil }
            return origin + max(0, Double(time.sampleTime) / time.sampleRate)
        }.max() ?? origin
    }
    private func pause() {
        clock.position = min(duration, currentPosition)
        run += 1
        tracks.forEach { $0.player.stop() }
        playing = false
    }
    func togglePause() {
        guard !tracks.isEmpty else { return }
        if playing { pause() } else { schedule(at: position >= duration ? 0 : position) }
    }
    func seek(_ seconds: Double) {
        if playing { schedule(at: seconds) } else { clock.position = max(0, min(seconds, duration)) }
    }
    func cycleRate() {
        rate = Self.rates[((Self.rates.firstIndex(of: rate) ?? 0) + 1) % Self.rates.count]
        if playing { pause(); speed.rate = rate; schedule(at: position) } else { speed.rate = rate }
    }
    func stop() {
        run += 1
        timer?.invalidate()
        timer = nil
        for track in tracks {
            track.player.stop()
            engine.detach(track.player)
            engine.detach(track.gain)
        }
        engine.stop()
        tracks = []
        sources = []
        playing = false
        duration = 0
        clock.position = 0
    }

    /// Gain that brings a track's speech to about -18 dBFS: the 90th percentile of 50 ms loudness among blocks that
    /// aren't silent, boosted by at most 24 dB and never turned down.
    nonisolated static func comfortableGain(_ url: URL) -> Float {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.processingFormat.sampleRate * 10))
        else { return 0 }
        let block = Int(file.processingFormat.sampleRate * 0.05)
        var levels: [Float] = []
        while (try? file.read(into: buffer)) != nil, buffer.frameLength > 0, let samples = buffer.floatChannelData?[0] {
            var offset = 0
            while offset + block <= Int(buffer.frameLength) {
                var rms: Float = 0
                vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(block))
                let decibels = 20 * log10(max(rms, 1e-9))
                if decibels > -65 { levels.append(decibels) }
                offset += block
            }
        }
        guard levels.count > 20 else { return 0 }
        levels.sort()
        let speech = levels[Int(Double(levels.count - 1) * 0.9)]
        return max(0, min(24, -18 - speech))
    }
}
