import Foundation

extension AppState {
    func installModels() async {
        do { try await engine.setup(model: preferences.model) }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    /// Queues local transcription. Recording a new meeting never waits for this.
    func transcribe(_ id: UUID) {
        guard !queued.contains(id), processingID != id else { return }
        queued.append(id)
        drainQueue()
    }
    func drainQueue() {
        runOperation { [weak self] in
            while let self, !Task.isCancelled, !self.queued.isEmpty {
                await self.process(self.queued.removeFirst())
            }
        }
    }
    func process(_ id: UUID) async {
        guard processingID == nil, !engine.busy, let meeting = meetings.first(where: { $0.id == id }) else { return }
        var configuration = preferences
        configuration.model = engine.ready(meeting.model) ? meeting.model : preferences.model
        guard engine.ready(configuration.model) else {
            update(id) { $0.status = .interrupted; $0.error = "Your recording is saved. Download the speech model in Settings → Transcription, then choose Transcribe Again." }
            return
        }
        processingID = id
        defer { processingID = nil }
        do {
            try Task.checkCancellation()
            update(id) { $0.status = .processing; $0.error = nil; $0.model = configuration.model }
            let segments = try await engine.transcribe(folder: library.folder(id), preferences: configuration)
            try Task.checkCancellation()
            update(id) {
                $0.replaceTranscript(segments)
                $0.status = $0.captureError == nil ? .ready : .failed
                $0.error = $0.captureError.map { "This recording is incomplete: \($0). Its audio is protected from automatic deletion." }
                    ?? (segments.isEmpty ? "No speech was detected. Check your microphone and Mac audio permissions in Settings → Recording." : nil)
            }
        } catch {
            update(id) {
                if $0.status == .processing { $0 = library.recover($0) }
                $0.status = .failed
                $0.error = error is CancellationError ? "Transcription cancelled. The audio is safe; choose Transcribe Again when ready." : error.localizedDescription
            }
        }
    }
    func analyze(_ id: UUID) {
        guard analyzingID == nil, let meeting = meetings.first(where: { $0.id == id }), !meeting.segments.isEmpty else { return }
        analysisFailure = nil
        let key = Keychain.read()
        guard !key.isEmpty else {
            hasOpenRouterKey = false
            analysisFailure = AnalysisFailure(id: id, message: "Add your OpenRouter API key in Settings → AI Analysis to analyze meetings.")
            return
        }
        let template = preferences.template
        let model = preferences.openRouterModel
        analyzingID = id
        analysisTask = Task {
            defer { analyzingID = nil; analysisTask = nil }
            do {
                let result = try await OpenRouter.analyze(meeting: meeting, template: template, model: model, key: key)
                try Task.checkCancellation()
                update(id) { $0.apply(result, template: template.name, model: model) }
            } catch is CancellationError {
            } catch {
                analysisFailure = AnalysisFailure(id: id, message: error.localizedDescription)
            }
        }
    }
    func cancelAnalysis() { analysisTask?.cancel() }
}
