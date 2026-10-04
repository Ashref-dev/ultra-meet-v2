import XCTest
import AVFoundation
@testable import UltraTranscribe

final class LibraryTests: XCTestCase {
    @MainActor
    func testCaptureFailureStopsAndPreservesFailureState() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        let meeting = Meeting(title: "Capture failure")
        try library.save(meeting)
        let state = try AppState(root: root)
        state.activeID = meeting.id
        state.captureFailed("Injected write failure")
        await state.stop(processAfter: false)
        XCTAssertNil(state.activeID)
        XCTAssertEqual(state.meetings.first?.status, .failed)
        XCTAssertEqual(state.meetings.first?.captureError, "Injected write failure")
    }

    @MainActor
    func testPartialRetryCheckpointDoesNotReplaceCompleteTranscript() throws {
        struct Checkpoint: Encodable { let segments: [TranscriptSegment] }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Retry recovery")
        meeting.status = .processing
        meeting.segments = [.init(start: 0, end: 30, text: "Complete original transcript.", source: "system")]
        try library.save(meeting)
        let partial = [TranscriptSegment(start: 0, end: 4, text: "Partial retry.", source: "system")]
        try JSONEncoder().encode(Checkpoint(segments: partial)).write(to: library.folder(meeting.id).appendingPathComponent("transcript.partial.json"))
        let state = try AppState(root: root)
        XCTAssertEqual(state.meetings.first?.segments.first?.text, "Complete original transcript.")
    }

    func testIncompleteCaptureIsNeverEligibleForAutomaticRetention() {
        var meeting = Meeting(title: "Incomplete capture")
        meeting.createdAt = Date(timeIntervalSince1970: 0)
        meeting.status = .ready
        meeting.captureError = "Audio write failed"
        XCTAssertFalse(meeting.audioExpired(after: 7, now: Date()))
    }

    @MainActor
    func testPendingImportAudioCannotBeDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        let meeting = Meeting(title: "Pending import")
        try library.save(meeting)
        let audio = library.folder(meeting.id).appendingPathComponent("imported.wav")
        try Data([0]).write(to: audio)
        let state = try AppState(root: root)
        state.pendingID = meeting.id
        state.deleteAudio(meeting.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))
    }

    @MainActor
    func testRuntimeWithInterpreterButNoDependenciesIsNotReady() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("Runtime/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let python = bin.appendingPathComponent("python")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: python)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: python.path)
        XCTAssertFalse(LocalEngine(root: root).runtimeReady)
    }

    func testMalformedMeetingDoesNotHideHealthyMeeting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        let healthy = Meeting(title: "Healthy")
        try library.save(healthy)
        let broken = Meeting(title: "Broken")
        try library.save(broken)
        try Data("broken JSON".utf8).write(to: library.folder(broken.id).appendingPathComponent("meeting.json"))
        XCTAssertEqual(try library.load().map(\.id), [healthy.id])
    }

    @MainActor
    func testCrashRecoveryPublishesCompletedWorkerArtifacts() throws {
        struct Checkpoint: Encodable { let segments: [TranscriptSegment] }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Checkpoint recovery")
        meeting.status = .processing
        try library.save(meeting)
        let segments = [TranscriptSegment(start: 0, end: 4, text: "The budget is approved.", source: "system")]
        try JSONEncoder().encode(Checkpoint(segments: segments)).write(to: library.folder(meeting.id).appendingPathComponent("transcript.json"))
        let state = try AppState(root: root)
        XCTAssertEqual(state.meetings.first?.segments.first?.text, segments.first?.text)
    }

    func testRecordingClockExcludesPausedTimeWithoutTimerDrift() {
        var clock = RecordingClock(started: 100)
        clock.pause(now: 105)
        XCTAssertEqual(clock.elapsed(now: 109), 5)
        clock.resume(now: 110)
        XCTAssertEqual(clock.elapsed(now: 115), 10)
    }
    func testRetentionPreservesUntranscribedAudio() {
        var meeting = Meeting(title: "Planning")
        meeting.createdAt = Date(timeIntervalSince1970: 0)
        meeting.status = .failed
        XCTAssertFalse(meeting.audioExpired(after: 7, now: Date()))
    }

    func testRetentionExpiresCompletedAudioOnly() {
        var meeting = Meeting(title: "Planning")
        meeting.createdAt = Date(timeIntervalSince1970: 0)
        meeting.status = .ready
        XCTAssertTrue(meeting.audioExpired(after: 7, now: Date()))
        XCTAssertFalse(meeting.audioExpired(after: 0, now: Date()))
    }

    func testMeetingLibraryRoundTripPreservesOriginalLanguages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Multilingual planning")
        meeting.status = .ready
        meeting.segments = [.init(start: 2, end: 8, text: "Le budget est approuvé. El lunes.", source: "system")]
        meeting.summary = "The budget is approved."
        try library.save(meeting)
        let restored = try XCTUnwrap(library.load().first)
        XCTAssertEqual(restored.segments.first?.text, meeting.segments.first?.text)
        XCTAssertEqual(restored.summary, meeting.summary)
    }

    func testDeletingAudioPreservesTranscriptAndNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        let meeting = Meeting(title: "Retention test")
        try library.save(meeting)
        try Data([0]).write(to: library.folder(meeting.id).appendingPathComponent("microphone.wav"))
        try library.removeAudio(meeting.id)
        XCTAssertEqual(try library.load().first?.id, meeting.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder(meeting.id).appendingPathComponent("microphone.wav").path))
    }

    @MainActor
    func testInterruptedProcessingRecoversRetainedMeeting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Interrupted test")
        meeting.status = .processing
        try library.save(meeting)
        let state = try AppState(root: root)
        XCTAssertEqual(state.meetings.first?.status, .interrupted)
        XCTAssertNotNil(state.meetings.first?.error)
    }

    func testImportDecodesAudioToRecoverablePCM() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.caf")
        let destination = root.appendingPathComponent("imported.wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<16000 { samples[index] = Float(sin(Double(index) * 0.1)) * 0.1 }
        }
        var file: AVAudioFile? = try AVAudioFile(forWriting: source, settings: format.settings)
        try file?.write(from: buffer)
        XCTAssertEqual(file?.length, 16000)
        file = nil
        let duration = try AudioImport.convert(source: source, destination: destination)
        XCTAssertEqual(duration, 1, accuracy: 0.001)
        XCTAssertEqual(try AVAudioFile(forReading: destination).length, 16000)
    }
}
