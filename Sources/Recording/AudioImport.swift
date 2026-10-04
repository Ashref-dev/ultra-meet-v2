import AVFoundation

enum AudioImport {
    static func convert(source: URL, destination: URL) throws -> Double {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        let output = try AVAudioFile(forWriting: destination, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192) else { throw AppError.message("Could not allocate an audio import buffer.") }
        while input.framePosition < input.length {
            try Task.checkCancellation()
            try input.read(into: buffer)
            try output.write(from: buffer)
        }
        return Double(input.length) / format.sampleRate
    }
}
