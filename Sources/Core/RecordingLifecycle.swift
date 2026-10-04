import Foundation

extension AppState {
    /// One click: creates an automatically named meeting and starts capturing immediately.
    func startRecording() {
        guard canStart else { return }
        starting = true
        startupTask = Task { await start(); startupTask = nil }
    }
    private func start() async {
        defer { starting = false; pendingID = nil }
        guard activeID == nil, !preparingToQuit else { return }
        error = nil
        var meeting = Meeting(title: Meeting.automaticTitle())
        meeting.titleEdited = false
        meeting.model = preferences.model
        meeting.source = preferences.source
        meeting.status = .processing
        meeting.captureError = "Recording setup did not finish."
        pendingID = meeting.id
        let recordingID = meeting.id
        recorder.onError = { [weak self] message in self?.captureFailed(message, for: recordingID) }
        do {
            try library.save(meeting)
            meetings.insert(meeting, at: 0)
            selectedID = meeting.id
            try await recorder.start(folder: library.folder(meeting.id), source: meeting.source)
            try Task.checkCancellation()
            activeID = meeting.id
            update(meeting.id) { $0.status = .recording; $0.captureError = nil }
            elapsed = 0
            recordingTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.recorder.paused, self.activeID != nil else { return }
                    self.elapsed = self.recorder.duration
                }
            }
            if let recordingTimer { RunLoop.main.add(recordingTimer, forMode: .common) }
        } catch is CancellationError {
            await recorder.stop()
            update(meeting.id) { $0.status = .failed; $0.captureError = "Recording setup did not finish."; $0.error = "Recording setup was cancelled." }
        } catch {
            await recorder.stop()
            update(meeting.id) { $0.status = .failed; $0.captureError = "Recording setup did not finish."; $0.error = error.localizedDescription }
            self.error = error.localizedDescription
        }
    }
    func togglePause() {
        guard activeID != nil, !stopping else { return }
        recorder.togglePause()
    }
    /// Finalizes the audio, queues local transcription and shows the meeting.
    func stopRecording() {
        guard activeID != nil, !stopping else { return }
        Task { await stop() }
    }
    func stop(processAfter: Bool = true) async {
        guard let id = activeID, !stopping else { return }
        stopping = true
        defer { stopping = false }
        recordingTimer?.invalidate()
        recordingTimer = nil
        elapsed = recorder.duration
        await recorder.stop()
        update(id) {
            $0.duration = elapsed
            $0.captureError = $0.captureError ?? recorder.captureFailure
            $0.status = $0.captureError == nil ? .interrupted : .failed
            if let failure = $0.captureError { $0.error = "Recording is incomplete: \(failure). Retained audio is protected from automatic deletion." }
        }
        activeID = nil
        guard processAfter && !preparingToQuit else { return }
        selectedID = id
        transcribe(id)
        showMeeting(id)
    }
    func captureFailed(_ message: String, for recordingID: UUID? = nil) {
        guard let id = recordingID ?? activeID else { error = message; return }
        update(id) { $0.captureError = message; $0.status = .failed; $0.error = "Recording is incomplete: \(message). Retained audio is protected from automatic deletion." }
        error = "Recording stopped: \(message). Audio captured so far remains on this Mac."
        if id == activeID && !stopping { Task { await stop(processAfter: false) } }
    }
    func cancelProcessing() {
        queued.removeAll()
        startupTask?.cancel()
        operationTask?.cancel()
        engine.cancel()
    }
    func prepareToQuit() async {
        preparingToQuit = true
        cancelProcessing()
        analysisTask?.cancel()
        if let startupTask { await startupTask.value }
        if let operationTask { await operationTask.value }
        await stop(processAfter: false)
    }
    func runOperation(_ work: @escaping @MainActor () async -> Void) {
        guard operationTask == nil, !preparingToQuit else { return }
        operationTask = Task {
            defer {
                operationTask = nil
                if !queued.isEmpty && !preparingToQuit && !Task.isCancelled { drainQueue() }
            }
            guard !Task.isCancelled else { return }
            await work()
        }
    }
}
