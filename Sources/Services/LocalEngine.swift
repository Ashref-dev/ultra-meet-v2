import Foundation

struct WorkerProgress: Decodable { let message: String; let fraction: Double }
struct WorkerTranscript: Decodable { let segments: [TranscriptSegment] }

@MainActor
final class LocalEngine: ObservableObject {
    @Published var message = ""
    @Published var fraction: Double = 0
    @Published var busy = false
    /// Lines transcribed so far for the folder being processed, read from the worker's checkpoint.
    @Published var partial: [TranscriptSegment] = []
    let root: URL
    private var process: Process?
    private var progressTimer: Timer?
    private var cancellationRequested = false
    private var partialStamp: Date?
    var models: URL { root.appendingPathComponent("Models") }
    var python: URL { root.appendingPathComponent("Runtime/bin/python") }
    var runtimeReady: Bool {
        guard FileManager.default.isExecutableFile(atPath: python.path),
              let installed = try? Data(contentsOf: root.appendingPathComponent("Runtime/.ready")),
              let required = try? Data(contentsOf: resource("runtime-requirements.txt")) else { return false }
        return installed == required
    }
    init(root: URL) { self.root = root }
    func ready(_ model: ASRModel) -> Bool {
        runtimeReady && FileManager.default.fileExists(atPath: models.appendingPathComponent("\(model.rawValue)/.ready").path)
    }
    func setup(model: ASRModel) async throws {
        try Task.checkCancellation()
        cancellationRequested = false
        guard !busy else { throw AppError.message("A local model task is already running.") }
        busy = true
        defer { busy = false }
        if !runtimeReady {
            message = "Installing the local Apple Silicon runtime…"
            let uv = Bundle.main.resourceURL!.appendingPathComponent("uv")
            if !FileManager.default.isExecutableFile(atPath: python.path) {
                try await execute(uv, arguments: ["venv", "--python", "3.12", root.appendingPathComponent("Runtime").path])
            }
            try await execute(uv, arguments: ["pip", "install", "--python", python.path, "-r", resource("runtime-requirements.txt").path])
            try Data(contentsOf: resource("runtime-requirements.txt")).write(to: root.appendingPathComponent("Runtime/.ready"), options: .atomic)
        }
        try await worker(["download", models.path, "--model", model.rawValue], progressFolder: models)
    }
    /// `live` follows a recording that is still being written, until `finish(folder:)`.
    func transcribe(folder: URL, preferences: Preferences, live: Bool = false) async throws -> [TranscriptSegment] {
        try Task.checkCancellation()
        cancellationRequested = false
        busy = true
        defer { busy = false }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(Self.finishFile))
        try await worker(["transcribe", folder.path, models.path, "--model", preferences.model.rawValue, "--languages", preferences.languages.joined(separator: ","), "--vocabulary", preferences.vocabulary] + (live ? ["--follow"] : []), progressFolder: folder)
        return try JSONDecoder().decode(WorkerTranscript.self, from: Data(contentsOf: folder.appendingPathComponent("transcript.json"))).segments
    }
    /// Tells a live transcription that the recording's files are complete.
    func finish(folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(Self.finishFile))
    }
    /// Transcribes one line again, optionally as a given language.
    func transcribe(line: TranscriptSegment, folder: URL, preferences: Preferences, language: String?) async throws -> TranscriptSegment {
        try Task.checkCancellation()
        guard !busy else { throw AppError.message("Wait for the current transcription to finish, then try again.") }
        cancellationRequested = false
        busy = true
        defer { busy = false }
        let output = folder.appendingPathComponent("line.json")
        try? FileManager.default.removeItem(at: output)
        try await worker(["line", folder.path, models.path, "--source", line.source, "--start", String(line.start), "--end", String(line.end), "--model", preferences.model.rawValue, "--language", language ?? "", "--languages", preferences.languages.joined(separator: ","), "--vocabulary", preferences.vocabulary], progressFolder: folder)
        var result = try JSONDecoder().decode(TranscriptSegment.self, from: Data(contentsOf: output))
        try? FileManager.default.removeItem(at: output)
        result.id = line.id
        return result
    }
    static let finishFile = ".finish"
    func cancel() {
        cancellationRequested = true
        if process?.isRunning == true { process?.terminate() }
        message = "Cancelling…"
    }
    private func resource(_ name: String) -> URL { Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Resources")! }
    private func worker(_ arguments: [String], progressFolder: URL) async throws {
        fraction = 0
        message = "Starting local transcription…"
        let progressURL = progressFolder.appendingPathComponent("progress.json")
        if FileManager.default.fileExists(atPath: progressURL.path) { try FileManager.default.removeItem(at: progressURL) }
        let partialURL = progressFolder.appendingPathComponent("transcript.partial.json")
        partial = []
        partialStamp = nil
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let data = try? Data(contentsOf: progressURL), let progress = try? JSONDecoder().decode(WorkerProgress.self, from: data) {
                    self.message = progress.message
                    self.fraction = progress.fraction
                }
                let stamp = (try? partialURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let stamp, stamp != self.partialStamp, let data = try? Data(contentsOf: partialURL), let transcript = try? JSONDecoder().decode(WorkerTranscript.self, from: data) {
                    self.partialStamp = stamp
                    self.partial = transcript.segments
                }
            }
        }
        defer { progressTimer?.invalidate(); progressTimer = nil; partial = [] }
        try await execute(python, arguments: [resource("worker.py").path] + arguments)
    }
    func execute(_ executable: URL, arguments: [String]) async throws {
        try Task.checkCancellation()
        guard !cancellationRequested else { throw CancellationError() }
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
        task.environment = environment
        let logURL = root.appendingPathComponent("engine.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let log = try FileHandle(forWritingTo: logURL)
        task.standardOutput = log
        task.standardError = log
        process = task
        defer { process = nil; try? log.close() }
        let status: Int32 = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                task.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
                do {
                    try task.run()
                    if Task.isCancelled || cancellationRequested { task.terminate() }
                } catch { continuation.resume(throwing: error) }
            }
        }, onCancel: {
            Task { @MainActor in
                if self.process === task { self.cancel() }
            }
        })
        try Task.checkCancellation()
        guard !cancellationRequested else { throw CancellationError() }
        guard status == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            throw AppError.message(status == 15 ? "Processing cancelled. The audio and any completed transcript remain on this Mac." : "Local processing failed (\(status)). \(String(output.suffix(1800)))")
        }
    }
}
