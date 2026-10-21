import Foundation
import XCTest
@testable import UltraTranscribe

final class VersusTests: XCTestCase {
    private func line(_ start: Double, _ end: Double, _ text: String, _ source: String = "microphone", confidence: Double? = nil) -> TranscriptSegment {
        TranscriptSegment(start: start, end: end, text: text, source: source, confidence: confidence)
    }
    private func column(_ id: String, _ lines: [TranscriptSegment], complete: Bool = true, status: VersusComparison.Status = .done) -> VersusComparison.Column {
        VersusComparison.Column(id: id, model: ASRModel(rawValue: id) ?? .best, segments: lines, status: status, complete: complete)
    }

    func testLinesWithSlightlyDifferentEdgesShareARowAndNextSentenceStartsANewOne() {
        let comparison = VersusComparison(columns: [
            column("best", [line(1.0, 4.0, "Hello team."), line(4.3, 7.0, "Let's start."), line(2.0, 3.5, "Hi there.", "system")]),
            column("small", [line(1.1, 3.9, "Hello, team!"), line(4.4, 7.2, "Lets start")])
        ])
        XCTAssertEqual(comparison.rows.count, 3)
        let first = comparison.rows[0]
        XCTAssertEqual(first.text("best"), "Hello team.")
        XCTAssertEqual(first.text("small"), "Hello, team!")
        XCTAssertEqual(comparison.rows[1].source, "system", "the other side never shares a row")
        XCTAssertNil(comparison.rows[1].text("small"))
        XCTAssertEqual(comparison.rows[2].text("small"), "Lets start")
    }

    func testAgreementIgnoresCaseAccentsAndPunctuationButMarksOtherWords() {
        let comparison = VersusComparison(columns: [
            column("best", [line(0, 3, "Résumé is ready."), line(4, 6, "Send the deck tomorrow")]),
            column("small", [line(0, 3, "resume IS ready"), line(4, 6, "Send the desk tomorrow")])
        ])
        let compared = comparison.compared(["best", "small"])
        XCTAssertTrue(comparison.agrees(comparison.rows[0], among: compared))
        XCTAssertFalse(comparison.agrees(comparison.rows[1], among: compared))
        XCTAssertEqual(comparison.unique(comparison.rows[1], column: "best", among: compared), ["deck"])
        XCTAssertEqual(comparison.unique(comparison.rows[1], column: "small", among: compared), ["desk"])
        XCTAssertEqual(comparison.unique(comparison.rows[1], column: "best", among: ["best"]), [], "nothing to compare with, nothing marked")
    }

    func testStatsCountMissedLinesOnlyAgainstCompleteColumns() {
        let comparison = VersusComparison(columns: [
            column("best", [line(0, 2, "One two", confidence: 0.3), line(3, 5, "Three")]),
            column("small", [line(0, 2, "One two")]),
            column("parakeet", [], complete: false, status: .running)
        ])
        let compared = comparison.compared(["best", "small", "parakeet"])
        XCTAssertEqual(compared, ["best", "small"])
        XCTAssertEqual(comparison.stats("best", among: compared), .init(lines: 2, words: 3, unsure: 1, missed: 0))
        XCTAssertEqual(comparison.stats("small", among: compared), .init(lines: 1, words: 2, unsure: 0, missed: 1))
        XCTAssertEqual(comparison.stats("parakeet", among: compared).missed, 0, "a run in progress hasn't missed anything yet")
    }

    func testColumnsPutTheMeetingFirstShowJobStatesAndRespectTheTrim() {
        var meeting = Meeting(title: "Weekly")
        meeting.model = .best
        meeting.duration = 60
        meeting.segments = [line(5, 8, "Before the trim"), line(20, 24, "Kept")]
        meeting.keepFrom = 10
        let runs = [VersusRun(model: .small, segments: [line(5, 8, "Cut"), line(20, 24, "Kept too")], seconds: 12)]
        let job = VersusJob(meetingID: meeting.id, pending: [.parakeet], current: .whisperTurbo, failures: [.granite: "Out of memory"])
        let columns = VersusComparison.columns(meeting: meeting, runs: runs, job: job, partial: [line(20, 23, "Partial")])
        XCTAssertEqual(columns.map(\.id), ["meeting", "small", "whisper-turbo", "parakeet", "granite"])
        XCTAssertEqual(columns[0].segments.map(\.text), ["Kept"])
        XCTAssertEqual(columns[1].segments.map(\.text), ["Kept too"])
        XCTAssertEqual(columns[1].seconds, 12)
        XCTAssertEqual(columns[2].status, .running)
        XCTAssertFalse(columns[2].complete)
        XCTAssertEqual(columns[2].segments.map(\.text), ["Partial"])
        XCTAssertEqual(columns[3].status, .waiting)
        XCTAssertEqual(columns[4].status, .failed("Out of memory"))
        let otherMeeting = VersusComparison.columns(meeting: meeting, runs: runs, job: VersusJob(meetingID: UUID(), pending: [.parakeet]), partial: [])
        XCTAssertEqual(otherMeeting.map(\.id), ["meeting", "small"], "another meeting's job never shows here")
    }

    func testMarkdownListsEveryShownModelPerLine() {
        let comparison = VersusComparison(columns: [column("best", [line(0, 2, "Hello")]), column("small", [])])
        let text = comparison.markdown(title: "Standup", shown: ["best", "small"])
        XCTAssertTrue(text.contains("# Standup · Versus"))
        XCTAssertTrue(text.contains("[00:00] You"))
        XCTAssertTrue(text.contains("- Qwen3-ASR 1.7B: Hello"))
        XCTAssertTrue(text.contains("- Qwen3-ASR 0.6B: (nothing)"))
    }

    func testRunsAreStoredApartFromTheTranscriptAndRemovedOneByOne() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        let id = UUID()
        try library.saveVersus(VersusRun(model: .small, segments: [line(0, 1, "a")], createdAt: Date(timeIntervalSince1970: 2), seconds: 3), for: id)
        try library.saveVersus(VersusRun(model: .best, segments: [line(0, 1, "b")], createdAt: Date(timeIntervalSince1970: 1), seconds: 4), for: id)
        try Data("not a run".utf8).write(to: library.versusFolder(id).appendingPathComponent("broken.json"))
        XCTAssertEqual(library.loadVersus(id).map(\.model), [.best, .small], "oldest first; unreadable files skipped")
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder(id).appendingPathComponent("transcript.json").path))
        try library.removeVersus(.best, for: id)
        XCTAssertEqual(library.loadVersus(id).map(\.model), [.small])
        try library.removeVersus(nil, for: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.versusFolder(id).path))
    }

    @MainActor
    func testFailedModelIsReportedWithoutTouchingTheMeetingAndUnprotectsIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try AppState(root: root)
        var meeting = Meeting(title: "Compared")
        meeting.status = .ready
        meeting.segments = [line(0, 2, "Original")]
        try state.library.save(meeting)
        state.meetings = [meeting]
        // No runtime is installed in tests, so the worker can't start: the model fails and the next one is tried.
        state.versus = VersusJob(meetingID: meeting.id, pending: [.small, .best])
        XCTAssertTrue(state.isProtected(meeting.id))
        state.continueVersus()
        XCTAssertEqual(state.versus?.current, .small)
        while state.versus?.isRunning == true { await state.operationTask?.value; await Task.yield() }
        XCTAssertEqual(Set(state.versus?.failures.keys.map { $0 } ?? []), [.small, .best])
        XCTAssertFalse(state.isProtected(meeting.id))
        XCTAssertEqual(state.meetings.first?.segments.map(\.text), ["Original"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.library.versusFolder(meeting.id).appendingPathComponent("small").path), "work folder cleaned up")
        state.removeVersus(meeting.id, model: .small)
        state.removeVersus(meeting.id, model: .best)
        XCTAssertNil(state.versus, "nothing left to show once failures are dismissed")
    }

    @MainActor
    func testRecordingOrTranscriptionPutsTheRunningModelBackInLine() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try AppState(root: root)
        let id = UUID()
        let began = expectation(description: "Comparison running")
        state.runOperation {
            began.fulfill()
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
        }
        await fulfillment(of: [began], timeout: 2)
        state.versus = VersusJob(meetingID: id, pending: [.best], current: .small)
        let operation = state.operationTask
        state.yieldVersus()
        await operation?.value
        XCTAssertEqual(state.versus?.pending, [.small, .best])
    }

    func testCompareRequiresADownloadedModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        MainActor.assumeIsolated {
            guard let state = try? AppState(root: root) else { return XCTFail("library") }
            let meeting = Meeting(title: "No models")
            state.meetings = [meeting]
            XCTAssertEqual(state.versusUnavailable(.best), "Not downloaded")
            state.compare(meeting.id, models: [.best])
            XCTAssertNil(state.versus)
        }
    }
}
