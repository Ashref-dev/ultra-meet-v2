import AppKit
import Foundation

/// One speech model's transcript of a meeting, made in Versus mode (experimental) to compare models on the same
/// audio. Runs are stored in the meeting's `Versus` folder, one file per model, apart from its transcript: comparing
/// never changes the meeting, and moving the meeting to the Trash takes them along.
struct VersusRun: Codable, Equatable, Identifiable {
    var model: ASRModel
    var segments: [TranscriptSegment]
    var createdAt = Date()
    /// Wall time of the run, model loading included.
    var seconds: Double
    var id: ASRModel { model }
}

/// Models still to transcribe one meeting for Versus mode. They run one at a time in the operation slot, after
/// recordings and regular transcriptions, and step aside for a recording that starts.
struct VersusJob: Equatable {
    let meetingID: UUID
    var pending: [ASRModel]
    var current: ASRModel?
    var failures: [ASRModel: String] = [:]
    var isRunning: Bool { current != nil || !pending.isEmpty }
    func includes(_ model: ASRModel) -> Bool { current == model || pending.contains(model) }
}

extension MeetingLibrary {
    func versusFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("Versus", isDirectory: true) }
    private func versusFile(_ model: ASRModel, for id: UUID) -> URL { versusFolder(id).appendingPathComponent("\(model.rawValue).json") }
    /// Finished runs, oldest first. A file that can't be read, for example a model from a newer version, is skipped.
    func loadVersus(_ id: UUID) -> [VersusRun] {
        ((try? FileManager.default.contentsOfDirectory(at: versusFolder(id), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(VersusRun.self, from: Data(contentsOf: $0)) }
            .sorted { $0.createdAt < $1.createdAt }
    }
    func saveVersus(_ run: VersusRun, for id: UUID) throws {
        try FileManager.default.createDirectory(at: versusFolder(id), withIntermediateDirectories: true)
        try JSONEncoder().encode(run).write(to: versusFile(run.model, for: id), options: .atomic)
    }
    /// Moves one model's run, or with `nil` the whole comparison, to the Trash.
    func removeVersus(_ model: ASRModel?, for id: UUID) throws {
        let url = model.map { versusFile($0, for: id) } ?? versusFolder(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try discard(url)
    }
}

/// Transcripts of one meeting lined up side by side. Lines of different models that cover the same speech of the
/// same side share a row, so each row reads as "what every model heard here".
struct VersusComparison {
    enum Status: Equatable { case done, running, waiting, failed(String) }
    struct Column: Identifiable, Equatable {
        /// `meeting` for the meeting's own transcript, otherwise the model's raw value.
        let id: String
        let model: ASRModel
        var segments: [TranscriptSegment]
        var seconds: Double?
        var status: Status = .done
        /// The whole meeting is in `segments`, so missing lines and differences mean something. A first run still in
        /// progress is not complete; a model running again shows its previous, complete run.
        var complete = true
        static let meeting = "meeting"
        var isMeeting: Bool { id == Self.meeting }
        var title: String { isMeeting ? "This meeting" : model.fullName }
        var subtitle: String { isMeeting ? model.fullName : model.maker == model.fullName ? model.name : model.maker }
    }
    struct Row: Identifiable {
        let id: Int
        let source: String
        let start: Double
        var end: Double
        var cells: [String: [TranscriptSegment]]
        /// Folded words per column: what agreement and differences are measured on.
        var words: [String: [String]] = [:]
        func text(_ column: String) -> String? { cells[column].map { $0.map(\.text).joined(separator: " ") } }
        var speaker: String { cells.values.first?.first?.speaker ?? "Speaker" }
    }
    struct Stats: Equatable { var lines = 0, words = 0, unsure = 0, missed = 0 }
    let columns: [Column]
    let rows: [Row]
    init(columns: [Column]) {
        self.columns = columns
        rows = Self.align(columns)
    }

    /// The meeting's transcript first, then each model: finished, running, waiting or failed. Lines outside a trim
    /// are left out, as everywhere else.
    static func columns(meeting: Meeting, runs: [VersusRun], job: VersusJob?, partial: [TranscriptSegment]) -> [Column] {
        let job = job?.meetingID == meeting.id ? job : nil
        var columns: [Column] = meeting.segments.isEmpty ? [] : [Column(id: Column.meeting, model: meeting.model, segments: meeting.keptSegments)]
        var models = runs.map(\.model)
        for model in [job?.current].compactMap({ $0 }) + (job?.pending ?? []) + (job?.failures.keys.sorted { $0.rawValue < $1.rawValue } ?? []) where !models.contains(model) {
            models.append(model)
        }
        for model in models {
            let run = runs.first { $0.model == model }
            let status: Status = job?.current == model ? .running : job?.pending.contains(model) == true ? .waiting : job?.failures[model].map { .failed($0) } ?? .done
            let lines = run?.segments ?? (status == .running ? partial : [])
            columns.append(Column(id: model.rawValue, model: model, segments: meeting.kept(lines), seconds: run?.seconds, status: status, complete: run != nil))
        }
        return columns
    }

    /// A line joins the latest row of its side when they overlap by at least a quarter of the shorter one, so
    /// slightly different utterance edges still line up, while the next sentence starts a row of its own.
    static func align(_ columns: [Column]) -> [Row] {
        let lines = columns.flatMap { column in column.segments.map { (column: column.id, line: $0) } }.sorted { $0.line.start < $1.line.start }
        var rows: [Row] = []
        var latest: [String: Int] = [:]
        for (column, line) in lines {
            if let index = latest[line.source] {
                let row = rows[index]
                let overlap = min(line.end, row.end) - max(line.start, row.start)
                if overlap > 0 && overlap >= 0.25 * min(line.duration, row.end - row.start) {
                    rows[index].end = max(row.end, line.end)
                    rows[index].cells[column, default: []].append(line)
                    continue
                }
            }
            latest[line.source] = rows.count
            rows.append(Row(id: rows.count, source: line.source, start: line.start, end: line.end, cells: [column: [line]]))
        }
        for index in rows.indices {
            rows[index].words = rows[index].cells.mapValues { words($0.map(\.text).joined(separator: " ")) }
        }
        return rows
    }
    /// Words folded like search, so case, accents and punctuation don't count as a difference.
    static func words(_ text: String) -> [String] {
        text.searchFolded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    /// The columns whose differences count: shown and complete.
    func compared(_ shown: Set<String>) -> [String] {
        columns.filter { shown.contains($0.id) && $0.complete }.map(\.id)
    }
    /// Every compared column heard the same words here, or nothing at all.
    func agrees(_ row: Row, among compared: [String]) -> Bool {
        let heard = compared.map { row.words[$0] ?? [] }
        return heard.allSatisfy { $0 == heard.first }
    }
    /// Words of one column that no other compared column has in this row.
    func unique(_ row: Row, column: String, among compared: [String]) -> Set<String> {
        let others = compared.filter { $0 != column }
        guard compared.contains(column), !others.isEmpty else { return [] }
        return Set(row.words[column] ?? []).subtracting(others.flatMap { row.words[$0] ?? [] })
    }
    /// Lines, words and unsure lines of a column, and rows where only the other compared columns heard speech.
    func stats(_ column: String, among compared: [String]) -> Stats {
        var stats = Stats()
        for row in rows {
            if let lines = row.cells[column] {
                stats.lines += lines.count
                stats.words += row.words[column]?.count ?? 0
                stats.unsure += lines.filter(\.isUncertain).count
            } else if compared.contains(column) && compared.contains(where: { row.cells[$0] != nil }) {
                stats.missed += 1
            }
        }
        return stats
    }
    /// The comparison as text: each row with what every shown column heard.
    func markdown(title: String, shown: Set<String>) -> String {
        let visible = columns.filter { shown.contains($0.id) }
        var lines = ["# \(title) · Versus", ""]
        lines += visible.map { "- \($0.title) (\($0.subtitle))\($0.seconds.map { ", transcribed in \(Meeting.timestamp($0))" } ?? "")" }
        for row in rows where visible.contains(where: { row.cells[$0.id] != nil }) {
            lines += ["", "[\(Meeting.timestamp(row.start))] \(row.speaker)"]
            lines += visible.map { "- \($0.title): \(row.text($0.id) ?? "(nothing)")" }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension AppState {
    /// Why a model can't join a comparison now, or nil when it can.
    func versusUnavailable(_ model: ASRModel) -> String? {
        guard engine.ready(model) else { return "Not downloaded" }
        var configuration = preferences
        configuration.model = model
        if model.languageMode == .one && configuration.spokenLanguages.isEmpty { return "Choose one of its languages in Settings → Transcription" }
        return nil
    }
    /// Transcribes a meeting with each model, one after another, for Versus mode. Models join a comparison already
    /// running for this meeting; another meeting's comparison has to finish or be cancelled first.
    func compare(_ id: UUID, models requested: [ASRModel]) {
        let models = requested.filter { versusUnavailable($0) == nil }
        guard !models.isEmpty, meetings.contains(where: { $0.id == id && !$0.audioDeleted }) else { return }
        if var job = versus, job.isRunning {
            guard job.meetingID == id else {
                error = "Versus mode is comparing models on another meeting. Wait for it to finish or cancel it there."
                return
            }
            job.pending += models.filter { !job.includes($0) }
            models.forEach { job.failures[$0] = nil }
            versus = job
        } else {
            let earlier = versus?.meetingID == id ? versus?.failures.filter { !models.contains($0.key) } : nil
            versus = VersusJob(meetingID: id, pending: models, failures: earlier ?? [:])
        }
        continueVersus()
    }
    /// Starts the next model when the engine is free. It is called after every operation, so a comparison picks up
    /// again by itself after a recording, a transcription or a model download.
    func continueVersus() {
        guard var job = versus, job.current == nil, activeID == nil, queued.isEmpty, operationTask == nil, !engine.busy, !preparingToQuit else { return }
        guard meetings.contains(where: { $0.id == job.meetingID && !$0.audioDeleted }) else { versus = nil; return }
        guard !job.pending.isEmpty else {
            if job.failures.isEmpty {
                versus = nil
                compactLibrary() // compression that stepped aside for the comparison continues
            }
            return
        }
        let model = job.pending.removeFirst()
        job.current = model
        versus = job
        runOperation { [weak self] in await self?.runVersus(model, for: job.meetingID) }
    }
    private func runVersus(_ model: ASRModel, for id: UUID) async {
        defer { if versus?.current == model { versus?.current = nil } }
        var configuration = preferences
        configuration.model = model
        let output = library.versusFolder(id).appendingPathComponent(model.rawValue, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let began = Date()
        do {
            try? FileManager.default.removeItem(at: output)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let segments = try await engine.transcribe(folder: library.folder(id), preferences: configuration, output: output)
            try Task.checkCancellation()
            try library.saveVersus(VersusRun(model: model, segments: segments, seconds: Date().timeIntervalSince(began)), for: id)
            versusRevision += 1
            if versus?.pending.isEmpty == true {
                notifyReady(id, title: "Comparison ready", body: "Every model has transcribed your meeting. Click to open it.")
            }
        } catch {
            // Cancel, Quit or a recording stopped it; for a recording, `yieldMaintenance` has put the model back in line.
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            versus?.failures[model] = error.localizedDescription
        }
    }
    /// Puts the running comparison model back at the front of the line and stops it, so a meeting's own recording or
    /// transcription goes first. It runs again from the start afterwards.
    func yieldVersus() {
        guard let current = versus?.current, let operationTask else { return }
        versus?.pending.insert(current, at: 0)
        operationTask.cancel()
    }
    func cancelVersus() {
        guard let job = versus else { return }
        versus = nil
        if job.current != nil {
            operationTask?.cancel()
            engine.cancel()
        }
    }
    /// Moves one model's run, or with `nil` the whole comparison, to the Trash, and forgets its failure.
    func removeVersus(_ id: UUID, model: ASRModel?) {
        if versus?.meetingID == id {
            if let model { versus?.failures[model] = nil } else { versus?.failures = [:] }
            if versus?.isRunning == false && versus?.failures.isEmpty == true { versus = nil }
        }
        do { try library.removeVersus(model, for: id) }
        catch { self.error = "The comparison couldn’t be moved to the Trash: \(error.localizedDescription)" }
        versusRevision += 1
    }
}
