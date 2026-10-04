import Foundation
import XCTest
@testable import UltraTranscribe

final class UpgradeTests: XCTestCase {
    func testSemanticVersionsCompareLikeSemver() throws {
        XCTAssertEqual(SemanticVersion("v0.6.0")?.description, "0.6.0")
        XCTAssertEqual(SemanticVersion("1.2")?.description, "1.2.0")
        XCTAssertNil(SemanticVersion("latest"))
        let ordered = ["0.5.0", "0.6.0-beta.2", "0.6.0-beta.10", "0.6.0", "0.6.1", "0.10.0", "1.0.0"].compactMap(SemanticVersion.init)
        XCTAssertEqual(ordered.count, 7)
        XCTAssertEqual(ordered, ordered.sorted())
        XCTAssertFalse(try XCTUnwrap(SemanticVersion("0.6.0")) < XCTUnwrap(SemanticVersion("v0.6.0")))
    }

    /// Shape of https://api.github.com/repos/Ashref-dev/ultra-meet-v2/releases (fields we read).
    func testNewestReleaseSkipsDraftsAndOlderVersions() throws {
        let json = #"""
        [
          {"tag_name": "v0.7.0", "name": "Draft", "body": "", "html_url": "https://github.com/Ashref-dev/ultra-meet-v2/releases/tag/v0.7.0", "draft": true, "prerelease": true, "assets": []},
          {"tag_name": "v0.6.1", "name": "Ultra Transcribe 0.6.1", "body": "Fixes", "html_url": "https://github.com/Ashref-dev/ultra-meet-v2/releases/tag/v0.6.1", "draft": false, "prerelease": true,
           "assets": [{"name": "Ultra-Transcribe-0.6.1.zip", "browser_download_url": "https://github.com/Ashref-dev/ultra-meet-v2/releases/download/v0.6.1/Ultra-Transcribe-0.6.1.zip", "size": 16549320}]},
          {"tag_name": "v0.5.0", "name": "Ultra Transcribe 0.5.0", "body": null, "html_url": "https://github.com/Ashref-dev/ultra-meet-v2/releases/tag/v0.5.0", "draft": false, "prerelease": true, "assets": []}
        ]
        """#
        let releases = try JSONDecoder().decode([Release].self, from: Data(json.utf8))
        let newest = try XCTUnwrap(Release.newest(releases, above: XCTUnwrap(SemanticVersion("0.6.0"))))
        XCTAssertEqual(newest.tag, "v0.6.1")
        XCTAssertEqual(newest.archive?.name, "Ultra-Transcribe-0.6.1.zip")
        XCTAssertNil(Release.newest(releases, above: try XCTUnwrap(SemanticVersion("0.6.1"))))
    }

    func testInstallerRefusesAnUnsignedDownload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        func bundle(_ name: String, version: String) throws -> URL {
            let app = root.appendingPathComponent("\(name).app")
            try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": "tn.achraf.ultratranscribe", "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
            return app
        }
        let installed = try bundle("Installed", version: "0.6.0")
        let download = try bundle("Download", version: "0.6.1")
        XCTAssertNil(UpdateInstaller.teamIdentifier(download))
        XCTAssertThrowsError(try UpdateInstaller.verify(download, replacing: installed))
    }

    func testTalkTimeAndAnalysisInputCarryTheSpeakerSplit() {
        var meeting = Meeting(title: "Sync")
        meeting.duration = 60
        meeting.notes = "Ask Sarah about pricing"
        meeting.segments = [
            .init(start: 0, end: 10, text: "We ship Friday.", source: "microphone", language: "English", confidence: 0.95),
            .init(start: 10, end: 40, text: "On a validé le budget.", source: "system", language: "French", confidence: 0.4),
            .init(start: 40, end: 50, text: "تمام", source: "system", language: "Arabic")
        ]
        XCTAssertEqual(meeting.talkTime.you, 10)
        XCTAssertEqual(meeting.talkTime.colleagues, 40)
        XCTAssertEqual(meeting.languages, ["English", "French", "Arabic"])
        XCTAssertEqual(meeting.segments.map(\.languageCode), ["EN", "FR", "AR"])
        XCTAssertTrue(meeting.segments[1].isUncertain)
        XCTAssertFalse(meeting.segments[2].isUncertain)
        let input = meeting.analysisInput
        XCTAssertTrue(input.contains("Talk time: You 00:10 (20%), Colleagues 00:40 (80%)."))
        XCTAssertTrue(input.contains("Languages heard: English, French, Arabic."))
        XCTAssertTrue(input.contains("Ask Sarah about pricing"))
        XCTAssertTrue(input.contains("[00:10] Colleagues: On a validé le budget. [unclear]"))
        XCTAssertTrue(input.contains("[00:00] You: We ship Friday.\n"))
        XCTAssertTrue(OpenRouter.instructions(AnalysisTemplate.defaults[0]).contains("never attribute a Colleagues line to You"))
    }

    func testSearchFoldsAccentsAndArabicSpelling() {
        XCTAssertTrue("أحمد قال: الميزانيّة جاهزة".searchFolded.contains("احمد"))
        XCTAssertTrue("الميزانية".searchFolded == "الميزانيه")
        XCTAssertTrue("Résumé de la réunion".searchFolded.contains("resume"))
        XCTAssertTrue("مستشفى".searchFolded.contains("مستشفي"))
    }

    func testOlderFilesDecodeWithNewDefaults() throws {
        let segment = try JSONDecoder().decode(TranscriptSegment.self, from: Data(#"{"id":"6C52F915-8620-4481-8934-BED13AB5BB84","start":1,"end":2,"text":"Hi","source":"system"}"#.utf8))
        XCTAssertNil(segment.confidence)
        XCTAssertFalse(segment.isUncertain)
        let preferences = try JSONDecoder().decode(Preferences.self, from: Data(#"{"model":"best","languages":["English","Arabic"]}"#.utf8))
        XCTAssertTrue(preferences.liveTranscription)
        XCTAssertTrue(preferences.globalShortcut)
        XCTAssertTrue(preferences.checkForUpdates)
        XCTAssertFalse(preferences.setupDone)
        var changed = preferences
        changed.setupDone = true
        changed.liveTranscription = false
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(changed))
        XCTAssertTrue(restored.setupDone)
        XCTAssertFalse(restored.liveTranscription)
    }

    func testCorrectionsSuggestNewNamesOnly() {
        XCTAssertEqual(AppState.newTerms(in: "Deploy to Kubernetes with Aziz in Q3", replacing: "Deploy to cooper nets with as is in cue three", known: "Achraf"), ["Kubernetes", "Aziz", "Q3"])
        XCTAssertEqual(AppState.newTerms(in: "Thanks Achraf", replacing: "Thanks a trough", known: "Achraf, Aziz"), [])
        XCTAssertEqual(AppState.newTerms(in: "their plan is fine", replacing: "there plan is fine", known: ""), [])
    }

    @MainActor
    func testEditingALineKeepsItAndOffersTerms() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Edit")
        meeting.status = .ready
        meeting.summary = "Old notes"
        meeting.segments = [.init(start: 0, end: 2, text: "we use cooper nets", source: "microphone", confidence: 0.4)]
        try library.save(meeting)
        let state = try AppState(root: root)
        state.editLine(meeting.id, line: meeting.segments[0].id, text: "we use Kubernetes")
        let saved = try XCTUnwrap(library.load().first)
        XCTAssertEqual(saved.segments[0].text, "we use Kubernetes")
        XCTAssertEqual(saved.segments[0].confidence, 1)
        XCTAssertEqual(saved.notesStale, true)
        XCTAssertEqual(state.termSuggestion?.terms, ["Kubernetes"])
        state.addTerms(["Kubernetes"])
        XCTAssertEqual(state.preferences.vocabulary, "Kubernetes")
        XCTAssertNil(state.termSuggestion)
    }

    @MainActor
    func testStoppingALiveRecordingFinishesItsTranscription() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MeetingLibrary(root: root)
        var meeting = Meeting(title: "Live")
        meeting.status = .recording
        try library.save(meeting)
        let state = try AppState(root: root)
        state.update(meeting.id) { $0.status = .recording }
        state.activeID = meeting.id
        state.liveID = meeting.id
        await state.stop()
        XCTAssertNil(state.activeID)
        XCTAssertEqual(state.processingID, meeting.id)
        XCTAssertTrue(state.queued.isEmpty, "A live recording is finished, not transcribed a second time")
        XCTAssertEqual(state.meetings.first?.status, .processing)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.folder(meeting.id).appendingPathComponent(LocalEngine.finishFile).path))
    }

    @MainActor
    func testSilenceIsTrackedPerSide() {
        let meter = LevelMeter()
        for _ in 0..<50 { meter.push(.init(you: 0, colleagues: 0.5), interval: 0.2, silent: (true, false)) }
        XCTAssertEqual(meter.youSilence, 10, accuracy: 0.001)
        XCTAssertEqual(meter.colleaguesSilence, 0)
        meter.push(.init(you: 0.4, colleagues: 0), interval: 0.2, silent: (false, true))
        XCTAssertEqual(meter.youSilence, 0)
        XCTAssertEqual(meter.colleaguesSilence, 0.2, accuracy: 0.001)
    }

    func testReplaceSwapsCopiesAndKeepsTheOldOneInTheTrash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Apps/Ultra Transcribe.app")
        let download = root.appendingPathComponent("Download/Ultra Transcribe.app")
        for (app, marker) in [(target, "old"), (download, "new")] {
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: app.appendingPathComponent("marker"))
        }
        try UpdateInstaller.replace(target, with: download)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path), ["Ultra Transcribe.app"], "No staged copy is left behind")
    }

    @MainActor
    func testLiveTranscriptionKeepsTheMeetingProtected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = try AppState(root: root)
        let id = UUID()
        XCTAssertFalse(state.isProtected(id))
        state.liveID = id
        XCTAssertTrue(state.isProtected(id))
    }
}
