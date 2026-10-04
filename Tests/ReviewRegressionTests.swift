import Foundation
import AVFoundation
import XCTest
@testable import UltraTranscribe

final class ReviewRegressionTests: XCTestCase {
    @MainActor
    func testCancelledOwnedOperationCannotPublishLateSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try AppState(root: root)
        let began = expectation(description: "Owned operation began")
        var continuation: CheckedContinuation<Void, Never>?
        var published = false
        state.runOperation {
            await withCheckedContinuation { continuation = $0; began.fulfill() }
            guard !Task.isCancelled else { return }
            published = true
        }
        await fulfillment(of: [began], timeout: 2)
        let operation = state.operationTask
        state.cancelProcessing()
        continuation?.resume()
        await operation?.value
        XCTAssertFalse(published)
        XCTAssertNil(state.operationTask)
    }

    func testReplacingTranscriptPreservesButMarksPreviousNotesStale() {
        var meeting = Meeting(title: "Updated recognition")
        meeting.summary = "Previous notes"
        meeting.replaceTranscript([.init(start: 0, end: 2, text: "New source", source: "system")])
        XCTAssertEqual(meeting.summary, "Previous notes")
        XCTAssertEqual(meeting.notesStale, true)
    }

    @MainActor
    func testInterruptedImportRemainsProtectedAfterSuccessfulProcessing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Interrupted import")
        meeting.status = .importing
        meeting.createdAt = Date(timeIntervalSince1970: 0)
        var recovered = library.recover(meeting)
        recovered.status = .ready
        XCTAssertNotNil(recovered.captureError)
        XCTAssertFalse(recovered.audioExpired(after: 7, now: Date()))
    }

    @MainActor
    func testFailureFromUnownedMicrophoneCannotChangeCapture() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: path) }
        let old = try AVAudioRecorder(url: path, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
        let capture = AudioRecorder()
        capture.microphoneFailed(old, message: "Stale encoder error")
        XCTAssertNil(capture.captureFailure)
    }

    @MainActor
    func testCancellationStopsSuccessorSubprocessPhase() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = LocalEngine(root: root)
        try await engine.execute(URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
        engine.cancel()
        do {
            try await engine.execute(URL(fileURLWithPath: "/usr/bin/true"), arguments: [])
            XCTFail("A cancelled operation launched its next subprocess.")
        } catch is CancellationError { }
    }

    func testRepeatedPauseDoesNotAdvanceElapsedTime() {
        var clock = RecordingClock(started: 100)
        clock.pause(now: 105)
        clock.pause(now: 110)
        XCTAssertEqual(clock.elapsed(now: 115), 5)
    }

    @MainActor
    func testRetentionPreservesReadyMeetingUnderProcessing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var preferences = Preferences()
        preferences.retentionDays = 0
        try library.savePreferences(preferences)
        var meeting = Meeting(title: "Protected notes processing")
        meeting.status = .ready
        meeting.createdAt = Date(timeIntervalSince1970: 0)
        try library.save(meeting)
        let audio = library.folder(meeting.id).appendingPathComponent("system.caf")
        try Data([0]).write(to: audio)
        let state = try AppState(root: root)
        state.processingID = meeting.id
        state.preferences.retentionDays = 7
        try state.applyRetention()
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
        XCTAssertFalse(state.meetings[0].audioDeleted)
    }
}
