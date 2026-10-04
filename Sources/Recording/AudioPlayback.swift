import AVFoundation
import Combine

@MainActor
final class AudioPlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var playing = false
    @Published var position: Double = 0
    @Published var duration: Double = 0
    private var player: AVAudioPlayer?
    private var timer: Timer?
    func play(_ url: URL, at seconds: Double = 0) throws {
        stop()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.delegate = self
        audio.currentTime = max(0, min(seconds, audio.duration))
        guard audio.play() else { throw AppError.message("This audio recording could not start playback.") }
        player = audio
        duration = audio.duration
        position = audio.currentTime
        playing = true
        startProgressTimer()
    }
    private func startProgressTimer() {
        timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func togglePause() {
        guard let player else { return }
        if playing { player.pause(); playing = false }
        else {
            playing = player.play()
            position = player.currentTime
            if playing && timer == nil { startProgressTimer() }
        }
    }
    func seek(_ seconds: Double) { player?.currentTime = seconds; position = seconds }
    func stop() { timer?.invalidate(); timer = nil; player?.stop(); player = nil; playing = false; duration = 0; position = 0 }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.playing = false
            self.position = self.duration
            self.timer?.invalidate()
            self.timer = nil
        }
    }
}
