import AVFoundation
import Combine

/// Plays a meeting's tracks together, in sync, at an adjustable speed. Tracks start at the same moment of the
/// recording, so a shared start time keeps You and Colleagues aligned.
@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let rates: [Float] = [1, 1.25, 1.5, 2]
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published private(set) var rate: Float = 1
    /// Track names playing, such as "microphone" and "system".
    @Published private(set) var sources: [String] = []
    private var players: [AVAudioPlayer] = []
    private var timer: Timer?

    func play(_ urls: [URL], at seconds: Double = 0) throws {
        stop()
        players = try urls.map { url in
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            return player
        }
        sources = urls.map { $0.deletingPathExtension().lastPathComponent }
        duration = players.map(\.duration).max() ?? 0
        guard start(at: seconds) else {
            stop()
            throw AppError.message("This audio recording could not start playback.")
        }
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.playing else { return }
                self.position = self.players.filter(\.isPlaying).map(\.currentTime).max() ?? self.position
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    /// Starts every track that still has audio at `seconds`, on one shared device time.
    private func start(at seconds: Double) -> Bool {
        let moment = (players.first?.deviceCurrentTime ?? 0) + 0.05
        var started = false
        for player in players {
            player.currentTime = max(0, min(seconds, player.duration))
            if seconds < player.duration { started = player.play(atTime: moment) || started }
        }
        position = seconds
        playing = started
        return started
    }
    func togglePause() {
        guard !players.isEmpty else { return }
        if playing {
            position = players.filter(\.isPlaying).map(\.currentTime).max() ?? position
            players.forEach { $0.pause() }
            playing = false
        } else {
            _ = start(at: position >= duration ? 0 : position)
        }
    }
    func seek(_ seconds: Double) {
        players.forEach { $0.pause() }
        if playing { _ = start(at: seconds) } else { position = seconds }
    }
    func cycleRate() {
        rate = Self.rates[((Self.rates.firstIndex(of: rate) ?? 0) + 1) % Self.rates.count]
        players.forEach { $0.rate = rate }
    }
    func stop() {
        timer?.invalidate()
        timer = nil
        players.forEach { $0.stop() }
        players = []
        sources = []
        playing = false
        duration = 0
        position = 0
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.players.contains(where: { $0 === player }), !self.players.contains(where: \.isPlaying) else { return }
            self.playing = false
            self.position = self.duration
        }
    }
}
