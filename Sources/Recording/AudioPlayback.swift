import Accelerate
import AVFoundation
import Combine

/// Plays a meeting's tracks together, in sync, at an adjustable speed. Tracks start at the same moment of the
/// recording, so one shared start keeps You and Colleagues aligned. Each track is brought to the same speech level,
/// up or down, so a hot microphone doesn't drown out the call, and a limiter keeps the mix from clipping. Recordings
/// on disk are never changed.
@MainActor
final class AudioPlayback: ObservableObject {
    static let rates: [Float] = [1, 1.25, 1.5, 2]
    /// The playhead, published on its own so ten updates a second redraw the player, not the whole transcript.
    final class Clock: ObservableObject { @Published var position: Double = 0 }
    let clock = Clock()
    @Published private(set) var playing = false
    /// Where playback starts over and where it stops, in seconds of the recording: all of it, or the kept part of a
    /// trimmed meeting.
    @Published private(set) var start: Double = 0
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
    /// The longest track, in seconds.
    private var length: Double = 0
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

    /// Plays from `seconds`, within `from` to `until` (`nil` is the end): see `limit`.
    func play(_ urls: [URL], at seconds: Double = 0, from: Double = 0, until: Double? = nil) throws {
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
        length = tracks.map { Double($0.file.length) / $0.file.processingFormat.sampleRate }.max() ?? 0
        limit(from: from, until: until)
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
    /// Plays only `from` to `until` of the recording (`nil` is its end), such as the kept part of a trimmed meeting.
    /// Playback already past a new end stops there; before a new start, it moves to it.
    func limit(from: Double, until: Double?) {
        guard !tracks.isEmpty else { return }
        let resume = playing
        if resume { pause() }
        duration = min(length, max(0, until ?? length))
        start = min(max(0, from), duration)
        clock.position = max(start, min(position, duration))
        if resume && position < duration { schedule(at: position) }
    }
    /// Starts every track that still has audio at `seconds`, together, a moment from now, and stops each at `duration`.
    /// From the end or past it, playback starts over, as it does once it has played to the end.
    @discardableResult
    private func schedule(at seconds: Double) -> Bool {
        run += 1
        let current = run
        tracks.forEach { $0.player.stop() }
        origin = seconds < duration ? max(start, seconds) : start
        remaining = 0
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.03))
        for track in tracks {
            let sampleRate = track.file.processingFormat.sampleRate
            let first = AVAudioFramePosition(origin * sampleRate)
            let last = min(track.file.length, AVAudioFramePosition((duration * sampleRate).rounded()))
            guard first < last else { continue }
            remaining += 1
            track.player.scheduleSegment(track.file, startingFrame: first, frameCount: AVAudioFrameCount(last - first), at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                Task { @MainActor in self?.finished(current) }
            }
            track.player.play(at: startTime)
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
        if playing { pause() } else { schedule(at: position) }
    }
    func seek(_ seconds: Double) {
        if playing { schedule(at: seconds) } else { clock.position = max(start, min(seconds, duration)) }
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
        length = 0
        start = 0
        duration = 0
        clock.position = 0
    }

    /// Gain that brings a track's speech to about -18 dBFS: the 90th percentile of 50 ms loudness among blocks that
    /// aren't silent, boosted by at most 24 dB or lowered by at most 12 dB.
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
        return max(-12, min(24, -18 - speech))
    }
}
