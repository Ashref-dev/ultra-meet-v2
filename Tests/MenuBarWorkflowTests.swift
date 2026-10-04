import Foundation
import XCTest
@testable import UltraTranscribe

final class MenuBarWorkflowTests: XCTestCase {
    func testLegacyPreferencesLoadWithDefaultTemplates() throws {
        let legacy = #"{"model":"large","source":"both","retentionDays":7,"generateEnglishNotes":true,"showDockIcon":true,"startInMenuBar":false,"launchAtLogin":false,"appearance":"system","language":"Auto-detect","vocabulary":"Achraf","openRouterModel":"openai/gpt-4.1-mini","cleanupInstructions":"Old"}"#
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(legacy.utf8))
        XCTAssertEqual(preferences.model, .large)
        XCTAssertEqual(preferences.vocabulary, "Achraf")
        XCTAssertEqual(preferences.openRouterModel, "openai/gpt-4.1-mini")
        XCTAssertEqual(preferences.templates.map(\.name), AnalysisTemplate.defaults.map(\.name))
        XCTAssertEqual(preferences.template.name, "Meeting notes")
        XCTAssertEqual(preferences.languages, [])
        let french = try JSONDecoder().decode(Preferences.self, from: Data(#"{"language":"French"}"#.utf8))
        XCTAssertEqual(french.languages, ["French"])
        var chosen = Preferences()
        chosen.languages = ["English", "Arabic"]
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(chosen)).languages, ["English", "Arabic"])
    }

    func testAnalysisTitleFormatsFromDifferentModels() {
        XCTAssertEqual(MeetingAnalysis.parse("## Q4 pricing review\n## Summary\nOk").title, "Q4 pricing review")
        XCTAssertEqual(MeetingAnalysis.parse("Title: Launch checklist\n\n## Summary").title, "Launch checklist")
        XCTAssertEqual(MeetingAnalysis.parse("**Hiring sync with Aziz**\n## Summary").title, "Hiring sync with Aziz")
        let generic = MeetingAnalysis.parse("# Meeting Notes\n\n## Summary\nWe agreed.")
        XCTAssertNil(generic.title)
        XCTAssertEqual(generic.notes, "## Summary\nWe agreed.")
        XCTAssertNil(MeetingAnalysis.parse("### You\n- [ ] Task").title)
    }

    func testModelRecommendationFollowsMacMemory() {
        let gigabyte: UInt64 = 1_073_741_824
        XCTAssertEqual(ASRModel.recommended(forMemory: 8 * gigabyte), .small)
        XCTAssertEqual(ASRModel.recommended(forMemory: 12 * gigabyte), .large)
        XCTAssertEqual(ASRModel.recommended(forMemory: 16 * gigabyte), .best)
        XCTAssertTrue(ASRModel.allCases.allSatisfy { $0.memoryGB < 8 })
    }

    func testTranscriptGroupsConsecutiveLinesBySpeaker() {
        let lines: [TranscriptSegment] = [
            .init(start: 8, end: 12, text: "Let's start.", source: "system"),
            .init(start: 13, end: 15, text: "Agenda first.", source: "system"),
            .init(start: 16, end: 18, text: "Sounds good.", source: "microphone"),
            .init(start: 19, end: 20, text: "Great.", source: "system")
        ]
        let blocks = SpeakerBlock.group(lines)
        XCTAssertEqual(blocks.map(\.source), ["system", "microphone", "system"])
        XCTAssertEqual(blocks.map(\.segments.count), [2, 1, 1])
        XCTAssertEqual(blocks[0].segments[0].speaker, "Colleagues")
        XCTAssertEqual(blocks[1].segments[0].speaker, "You")
    }

    func testSelectedTemplatePersists() throws {
        var preferences = Preferences()
        preferences.templates.append(AnalysisTemplate(name: "CTO meeting", prompt: "Architecture first."))
        preferences.templateID = preferences.templates.last?.id
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(restored.template.name, "CTO meeting")
        XCTAssertEqual(restored.template.prompt, "Architecture first.")
    }

    func testLegacyMeetingKeepsItsName() throws {
        let legacy = #"{"id":"6C52F915-8620-4481-8934-BED13AB5BB84","title":"Budget review","createdAt":0,"duration":12,"status":"ready","source":"both","model":"large","segments":[],"notes":"","summary":"","audioDeleted":false,"cloudProcessed":true}"#
        var meeting = try JSONDecoder().decode(Meeting.self, from: Data(legacy.utf8))
        meeting.apply(MeetingAnalysis(title: "Something else", notes: "Notes"), template: "Meeting notes", model: "m")
        XCTAssertEqual(meeting.title, "Budget review")
        XCTAssertEqual(meeting.summary, "Notes")
    }

    func testAnalysisRenamesAutomaticallyNamedMeetingOnly() {
        var automatic = Meeting(title: Meeting.automaticTitle())
        automatic.titleEdited = false
        automatic.apply(MeetingAnalysis(title: "Q3 pricing with Acme", notes: "## Summary"), template: "Sales call", model: "google/gemini-2.5-flash")
        XCTAssertEqual(automatic.title, "Q3 pricing with Acme")
        XCTAssertEqual(automatic.analysisTemplate, "Sales call")
        XCTAssertEqual(automatic.notesStale, false)

        var named = Meeting(title: "My name")
        named.titleEdited = true
        named.apply(MeetingAnalysis(title: "AI name", notes: "Notes"), template: "Meeting notes", model: "m")
        XCTAssertEqual(named.title, "My name")
    }

    func testAnalysisOutputSplitsTitleFromNotes() {
        let parsed = MeetingAnalysis.parse("```markdown\n# \"Hiring plan for Q4\"\n\n## Summary\nWe agreed.\n```")
        XCTAssertEqual(parsed.title, "Hiring plan for Q4")
        XCTAssertEqual(parsed.notes, "## Summary\nWe agreed.")
        let untitled = MeetingAnalysis.parse("## Summary\nNo heading.")
        XCTAssertNil(untitled.title)
        XCTAssertEqual(untitled.notes, "## Summary\nNo heading.")
    }

    func testTranscriptLabelsSpeakersForAnalysis() {
        var meeting = Meeting(title: "Sync")
        meeting.segments = [
            .init(start: 1, end: 3, text: "Let's ship Friday.", source: "microphone", language: "English"),
            .init(start: 4, end: 6, text: "هذه تجربة بلغة عربية.", source: "system", language: "Arabic")
        ]
        XCTAssertEqual(meeting.transcript, "[00:01] You: Let's ship Friday.\n[00:04] Colleagues: هذه تجربة بلغة عربية.")
        XCTAssertFalse(meeting.segments[0].isRightToLeft)
        XCTAssertTrue(meeting.segments[1].isRightToLeft)
        XCTAssertTrue(TranscriptSegment(start: 0, end: 1, text: "مرحبا", source: "system").isRightToLeft)
    }

    func testAutomaticTitleAndSourceToggles() {
        XCTAssertTrue(Meeting.automaticTitle(Date(timeIntervalSince1970: 0)).hasPrefix("Meeting · "))
        XCTAssertEqual(AudioSource.from(microphone: true, system: false), .microphone)
        XCTAssertNil(AudioSource.from(microphone: false, system: false))
        XCTAssertEqual(Meeting.timestamp(3725), "1:02:05")
    }

    @MainActor
    func testTalkShareCountsSpeakingTimePerSource() {
        let meter = LevelMeter()
        XCTAssertNil(meter.youShare)
        for _ in 0..<30 { meter.push(.init(you: 0.8, colleagues: 0), interval: 0.1) }
        for _ in 0..<10 { meter.push(.init(you: 0, colleagues: 0.7), interval: 0.1) }
        XCTAssertEqual(meter.youShare ?? 0, 0.75, accuracy: 0.001)
        XCTAssertEqual(meter.history.count, LevelMeter.length)
        XCTAssertEqual(LevelMeter.normalized(decibels: -60), 0)
        XCTAssertEqual(LevelMeter.normalized(decibels: 0), 1)
    }

    @MainActor
    func testQueuedTranscriptionWithoutModelKeepsAudioAndExplains() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "No model yet")
        meeting.status = .interrupted
        try library.save(meeting)
        let state = try AppState(root: root)
        state.transcribe(meeting.id)
        await state.operationTask?.value
        XCTAssertTrue(state.queued.isEmpty)
        XCTAssertEqual(state.meetings.first?.status, .interrupted)
        XCTAssertTrue(state.meetings.first?.error?.contains("Download the speech model") == true)
    }

    @MainActor
    func testAnalysisWithoutKeyExplainsInline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Needs key")
        meeting.segments = [.init(start: 0, end: 1, text: "Hello", source: "microphone")]
        try library.save(meeting)
        let state = try AppState(root: root)
        state.readKey = { "" }
        state.analyze(meeting.id)
        XCTAssertNil(state.analyzingID)
        XCTAssertEqual(state.analysisFailure?.id, meeting.id)
    }
}
