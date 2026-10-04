import AppKit
import Foundation

/// Names or terms a correction introduced, offered for the custom vocabulary.
struct TermSuggestion: Equatable { let meetingID: UUID; let terms: [String] }

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
    /// Transcribes while the meeting records, so Stop only has the last sentence left. Skipped when the engine is
    /// busy with another meeting or the model isn't installed; the meeting is then transcribed after Stop as usual.
    func beginLiveTranscription(_ id: UUID) {
        guard preferences.liveTranscription, operationTask == nil, !engine.busy, engine.ready(preferences.model) else { return }
        runOperation { [weak self] in await self?.process(id, live: true) }
    }
    func process(_ id: UUID, live requested: Bool = false) async {
        // A recording stopped before its live task started is finished files: transcribe it normally, once.
        let live = requested && activeID == id
        guard processingID == nil, liveID == nil, !engine.busy, let meeting = meetings.first(where: { $0.id == id }) else { return }
        if requested && !live && queued.contains(id) { return }
        var configuration = preferences
        configuration.model = engine.ready(meeting.model) ? meeting.model : preferences.model
        guard engine.ready(configuration.model) else {
            if !live { update(id) { $0.status = .interrupted; $0.error = "Your recording is saved. Download the speech model in Settings → Transcription, then choose Transcribe Again." } }
            return
        }
        if live { liveID = id } else { processingID = id }
        defer { liveID = nil; processingID = nil }
        do {
            try Task.checkCancellation()
            update(id) {
                if !live { $0.status = .processing; $0.error = nil }
                $0.model = configuration.model
            }
            let segments = try await engine.transcribe(folder: library.folder(id), preferences: configuration, live: live)
            try Task.checkCancellation()
            update(id) {
                $0.replaceTranscript(segments)
                $0.status = $0.captureError == nil ? .ready : .failed
                $0.error = $0.captureError.map { "This recording is incomplete: \($0). Its audio is protected from automatic deletion." }
                    ?? (segments.isEmpty ? "No speech was detected. Check your microphone and Mac audio permissions in Settings → Recording." : nil)
            }
            notifyReady(id)
        } catch {
            // A live transcription that ends before Stop (or with a recording that won't be transcribed) leaves the
            // meeting alone; Stop then transcribes it as usual.
            guard processingID == id else { return }
            if live && !(error is CancellationError) && !preparingToQuit {
                queued.append(id)
                return
            }
            update(id) {
                if $0.status == .processing { $0 = library.recover($0) }
                $0.status = .failed
                $0.error = error is CancellationError ? "Transcription cancelled. The audio is safe; choose Transcribe Again when ready." : error.localizedDescription
            }
        }
    }
    func notifyReady(_ id: UUID) {
        guard preferences.notifyWhenReady, Notifier.available, NSApp?.isActive == false, let meeting = meetings.first(where: { $0.id == id }), !meeting.segments.isEmpty else { return }
        Notifier.post(id: id.uuidString, title: "Transcript ready", body: "\(meeting.title) · \(meeting.segments.count) lines", info: ["meeting": id.uuidString])
    }
    /// Transcribes one line again, as the given language or detecting it.
    func retranscribe(_ id: UUID, line: TranscriptSegment, as language: String?) {
        guard redoingLineID == nil, let meeting = meetings.first(where: { $0.id == id }), !meeting.audioDeleted else { return }
        guard operationTask == nil, !engine.busy else {
            error = "Wait for the current transcription to finish, then transcribe the line again."
            return
        }
        var configuration = preferences
        configuration.model = engine.ready(meeting.model) ? meeting.model : preferences.model
        guard engine.ready(configuration.model) else {
            error = "Download the speech model in Settings → Transcription first."
            return
        }
        redoingLineID = line.id
        runOperation { [weak self] in
            guard let self else { return }
            defer { self.redoingLineID = nil }
            do {
                let result = try await self.engine.transcribe(line: line, folder: self.library.folder(id), preferences: configuration, language: language)
                self.update(id) { meeting in
                    guard let index = meeting.segments.firstIndex(where: { $0.id == line.id }) else { return }
                    var segments = meeting.segments
                    segments[index].text = result.text.isEmpty ? segments[index].text : result.text
                    segments[index].language = result.language ?? language
                    segments[index].confidence = result.confidence
                    meeting.replaceTranscript(segments)
                }
            } catch is CancellationError {
            } catch {
                self.error = "This line could not be transcribed again: \(error.localizedDescription)"
            }
        }
    }
    /// Saves a corrected line and offers new names or terms for the custom vocabulary.
    func editLine(_ id: UUID, line: UUID, text: String) {
        let corrected = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let meeting = meetings.first(where: { $0.id == id }), let index = meeting.segments.firstIndex(where: { $0.id == line }), !corrected.isEmpty, corrected != meeting.segments[index].text else { return }
        let terms = Self.newTerms(in: corrected, replacing: meeting.segments[index].text, known: preferences.vocabulary)
        update(id) {
            var segments = $0.segments
            segments[index].text = corrected
            segments[index].confidence = 1
            $0.replaceTranscript(segments)
        }
        termSuggestion = terms.isEmpty ? nil : TermSuggestion(meetingID: id, terms: terms)
    }
    /// Capitalized words or words with digits that a correction added: likely names, products or jargon.
    nonisolated static func newTerms(in corrected: String, replacing original: String, known vocabulary: String) -> [String] {
        let old = Set(original.lowercased().components(separatedBy: .alphanumerics.inverted))
        let known = Set(vocabulary.lowercased().components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        var terms: [String] = []
        for word in corrected.components(separatedBy: .whitespacesAndNewlines).map({ $0.trimmingCharacters(in: .punctuationCharacters) }) where word.count >= 2 {
            let lower = word.lowercased()
            guard !old.contains(lower), !known.contains(lower), !terms.contains(word), word.first?.isUppercase == true || word.contains(where: \.isNumber) else { continue }
            terms.append(word)
        }
        return Array(terms.prefix(4))
    }
    func addTerms(_ terms: [String]) {
        let existing = preferences.vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.vocabulary = ([existing].filter { !$0.isEmpty } + terms).joined(separator: ", ")
        savePreferences()
        termSuggestion = nil
    }
    func analyze(_ id: UUID) {
        guard analyzingID == nil, let meeting = meetings.first(where: { $0.id == id }), !meeting.segments.isEmpty else { return }
        analysisFailure = nil
        let key = readKey()
        guard !key.isEmpty else {
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
                let previous = meetings.first { $0.id == id }?.title
                update(id) { $0.apply(result, template: template.name, model: model) }
                if meetings.first(where: { $0.id == id })?.title != previous { flashRename(id) }
            } catch is CancellationError {
            } catch {
                analysisFailure = AnalysisFailure(id: id, message: error.localizedDescription)
            }
        }
    }
    func cancelAnalysis() { analysisTask?.cancel() }
    /// Briefly highlights a meeting the AI just renamed, so the new name is noticed in the sidebar.
    func flashRename(_ id: UUID) {
        renamedID = id
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if renamedID == id { renamedID = nil }
        }
    }
}
