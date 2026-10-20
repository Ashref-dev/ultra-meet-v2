import Foundation
import XCTest
@testable import UltraTranscribe

final class TrimTests: XCTestCase {
    func testOlderMeetingsDecodeUntrimmed() throws {
        let legacy = #"{"id":"6C52F915-8620-4481-8934-BED13AB5BB84","title":"Budget review","createdAt":0,"duration":12,"status":"ready","source":"both","model":"large","segments":[{"id":"0F1D2C3B-4A59-4687-9A1B-2C3D4E5F6A7B","start":1,"end":4,"text":"Hi","source":"system"}],"notes":"","summary":"","audioDeleted":false}"#
        let meeting = try JSONDecoder().decode(Meeting.self, from: Data(legacy.utf8))
        XCTAssertNil(meeting.keepFrom)
        XCTAssertNil(meeting.keepUntil)
        XCTAssertFalse(meeting.isTrimmed)
        XCTAssertEqual(meeting.keptSegments, meeting.segments)
        XCTAssertEqual(meeting.keptRange, 0...12)
        XCTAssertEqual(meeting.keptDuration, 12)
    }

    func testTrimmedLinesAreLeftOutOfEverythingShared() {
        var meeting = Meeting(title: "Standup")
        meeting.duration = 120
        meeting.summary = "Old notes"
        meeting.notesStale = false
        meeting.segments = [
            .init(start: 2, end: 8, text: "Can you hear me?", source: "microphone", language: "English"),
            .init(start: 10, end: 30, text: "On commence.", source: "system", language: "French"),
            .init(start: 30, end: 40, text: "We ship Friday.", source: "microphone", language: "English"),
            .init(start: 40, end: 50, text: "Forgot to stop.", source: "system", language: "Arabic")
        ]
        meeting.trim(from: 10, until: 40)
        XCTAssertTrue(meeting.isTrimmed)
        XCTAssertEqual(meeting.keptSegments.map(\.text), ["On commence.", "We ship Friday."], "A line that starts where the kept part ends is left out")
        XCTAssertEqual(meeting.segments.count, 4, "Trimming never removes lines")
        XCTAssertEqual(meeting.keptDuration, 30)
        XCTAssertEqual(meeting.transcript, "[00:10] Colleagues: On commence.\n[00:30] You: We ship Friday.")
        XCTAssertEqual(meeting.talkTime.you, 10)
        XCTAssertEqual(meeting.talkTime.colleagues, 20)
        XCTAssertEqual(meeting.languages, ["French", "English"])
        let input = meeting.analysisInput
        XCTAssertTrue(input.contains("00:30 long."))
        XCTAssertTrue(input.contains("Talk time: You 00:10 (33%), Colleagues 00:20 (67%)."))
        XCTAssertFalse(input.contains("Can you hear me?"))
        XCTAssertFalse(input.contains("Forgot to stop."))
        XCTAssertTrue(meeting.markdown.contains(" · 00:30\n"))
        XCTAssertFalse(meeting.markdown.contains("Forgot to stop."))
        XCTAssertEqual(meeting.notesStale, true, "Changing the trim puts AI notes out of date, like an edit")
    }

    func testTrimSnapsToTheEdgesAndCanBeRestored() {
        var meeting = Meeting(title: "Edges")
        meeting.duration = 60
        meeting.segments = [.init(start: 0, end: 5, text: "Hello", source: "microphone")]
        meeting.trim(from: 0.6, until: 59.5)
        XCTAssertFalse(meeting.isTrimmed, "Within a second of the start or end means the start or end")
        meeting.trim(from: 40, until: 30)
        XCTAssertFalse(meeting.isTrimmed, "A trim that keeps nothing is ignored")
        meeting.trim(from: nil, until: 20)
        XCTAssertEqual(meeting.keptRange, 0...20)
        meeting.trim(from: nil, until: nil)
        XCTAssertFalse(meeting.isTrimmed)
        XCTAssertNotEqual(meeting.notesStale, true, "Without AI notes there is nothing to put out of date")
        meeting.keepFrom = 90
        meeting.keepUntil = 70
        XCTAssertEqual(meeting.keptRange, 60...60, "Saved bounds outside the recording never reverse the range")
        XCTAssertTrue(meeting.keptSegments.isEmpty)
    }

    @MainActor
    func testMapHandlesKeepFiveSecondsAndSnapToTheEdges() {
        let map = ConversationMap(segments: [], duration: 100)
        XCTAssertEqual(map.moved(10...50, start: true, to: 48), 45...50)
        XCTAssertEqual(map.moved(10...50, start: true, to: 0.8), 0...50)
        XCTAssertEqual(map.moved(10...50, start: false, to: 12), 10...15)
        XCTAssertEqual(map.moved(10...50, start: false, to: 99.4), 10...100)
        XCTAssertEqual(map.moved(10...12, start: true, to: 11), 10...12, "A shorter kept part is never widened by grabbing a handle")
    }

    @MainActor
    func testTrimIsSavedAndRestoredThroughTheLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Trim round trip")
        meeting.status = .ready
        meeting.duration = 90
        meeting.summary = "Notes"
        meeting.notesStale = false
        meeting.segments = [
            .init(start: 5, end: 10, text: "Before", source: "microphone"),
            .init(start: 20, end: 30, text: "Kept", source: "system"),
            .init(start: 70, end: 80, text: "After", source: "system")
        ]
        try library.save(meeting)
        let state = try AppState(root: root)
        state.trim(meeting.id, from: 20, until: 30)
        var saved = try XCTUnwrap(library.load().first)
        XCTAssertEqual(saved.keepFrom, 20)
        XCTAssertEqual(saved.keepUntil, 30)
        XCTAssertEqual(saved.keptSegments.map(\.text), ["Kept"])
        XCTAssertEqual(saved.segments.count, 3)
        XCTAssertEqual(saved.notesStale, true)

        state.analyzingID = meeting.id
        state.trim(meeting.id, from: nil, until: nil)
        state.analyzingID = nil
        state.activeID = meeting.id
        state.trim(meeting.id, from: nil, until: nil)
        state.activeID = nil
        XCTAssertEqual(try XCTUnwrap(library.load().first).keepFrom, 20, "A meeting being recorded or analyzed is never trimmed")

        state.trim(meeting.id, from: nil, until: nil)
        saved = try XCTUnwrap(library.load().first)
        XCTAssertNil(saved.keepFrom)
        XCTAssertNil(saved.keepUntil)
        XCTAssertEqual(saved.keptSegments.map(\.text), ["Before", "Kept", "After"])
    }
}
