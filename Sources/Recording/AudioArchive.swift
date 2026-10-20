import AVFoundation

/// Transcribed meetings keep their audio as FLAC: lossless, full 48 kHz, about a ninth of the recorded size.
enum AudioArchive {
    /// Converts each uncompressed track in `folder` (WAV, CAF, AIFF) to FLAC and returns the bytes saved. An original
    /// is deleted only after its FLAC copy is read back and holds the same samples. Integer audio is kept exactly;
    /// 32-bit float audio (Mac audio recorded before 0.8, some imports) is stored as 16-bit, like every recording now:
    /// 96 dB of range, far below any microphone's noise.
    @discardableResult
    static func compact(folder: URL) throws -> Int64 {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        var saved: Int64 = 0
        for url in files where ["wav", "caf", "aiff"].contains(url.pathExtension.lowercased()) {
            saved += try compact(url)
        }
        return saved
    }

    static func compact(_ url: URL) throws -> Int64 {
        let destination = url.deletingPathExtension().appendingPathExtension("flac")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return 0 }
        let source = try AVAudioFile(forReading: url)
        let description = source.fileFormat.streamDescription.pointee
        guard description.mFormatID == kAudioFormatLinearPCM, source.length > 0 else { return 0 }
        let isFloat = description.mFormatFlags & kAudioFormatFlagIsFloat != 0
        guard isFloat || description.mBitsPerChannel == 16 || description.mBitsPerChannel == 24 else { return 0 } // FLAC can't hold 32-bit integers exactly
        let scratch = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let encoded = scratch.appendingPathComponent(destination.lastPathComponent)
        try encode(source, to: encoded, roundingTo16Bit: isFloat)
        try verify(original: url, copy: encoded, tolerance: isFloat ? 0.5001 / 32768 : 0)
        let before = size(url)
        try FileManager.default.moveItem(at: encoded, to: destination)
        try FileManager.default.removeItem(at: url)
        return before - size(destination)
    }

    private static let chunk: AVAudioFrameCount = 48000 * 10

    /// AVAudioFile always writes 24-bit FLAC. Float audio is first rounded to the 16-bit grid, so the encoder's
    /// unused low bits cost nothing and the file is as small as a 16-bit FLAC.
    private static func encode(_ source: AVAudioFile, to url: URL, roundingTo16Bit: Bool) throws {
        let format = source.processingFormat
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: format.channelCount]
        let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw AppError.message("Could not allocate an audio buffer.") }
        while source.framePosition < source.length {
            try Task.checkCancellation()
            try source.read(into: buffer)
            if roundingTo16Bit, let channels = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    for index in 0..<Int(buffer.frameLength) { channels[channel][index] = (clipped(channels[channel][index]) * 32768).rounded() / 32768 }
                }
            }
            try output.write(from: buffer)
        }
    }
    private static func clipped(_ sample: Float) -> Float { min(max(sample, -1), 32767 / 32768) }

    /// Same length, and every sample within `tolerance` (0 for integer audio). Reads return uneven chunk sizes
    /// (CAF packets), so the two files are walked side by side rather than chunk by chunk.
    private static func verify(original: URL, copy: URL, tolerance: Float) throws {
        let mismatch = AppError.message("The compressed audio doesn't match the recording, so the recording was kept.")
        let first = try AVAudioFile(forReading: original), second = try AVAudioFile(forReading: copy)
        let channels = Int(first.processingFormat.channelCount)
        guard first.length == second.length, Int(second.processingFormat.channelCount) == channels,
              let a = AVAudioPCMBuffer(pcmFormat: first.processingFormat, frameCapacity: chunk),
              let b = AVAudioPCMBuffer(pcmFormat: second.processingFormat, frameCapacity: chunk) else { throw mismatch }
        var (left, right, compared) = (0, 0, AVAudioFramePosition(0))
        while compared < first.length {
            try Task.checkCancellation()
            if left == Int(a.frameLength) { try first.read(into: a); left = 0 }
            if right == Int(b.frameLength) { try second.read(into: b); right = 0 }
            let count = min(Int(a.frameLength) - left, Int(b.frameLength) - right)
            guard count > 0, let x = a.floatChannelData, let y = b.floatChannelData else { throw mismatch }
            for channel in 0..<channels {
                for index in 0..<count where abs(clipped(x[channel][left + index]) - y[channel][right + index]) > tolerance { throw mismatch }
            }
            left += count
            right += count
            compared += AVAudioFramePosition(count)
        }
    }

    private static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
