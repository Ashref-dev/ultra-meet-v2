import Foundation

enum MeetingStatus: String, Codable { case importing, recording, processing, ready, failed, interrupted }
enum AudioSource: String, Codable, CaseIterable, Identifiable {
    case both, microphone, system
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "You + colleagues"
        case .microphone: return "Only you (microphone)"
        case .system: return "Only colleagues (Mac audio)"
        }
    }
    var usesMicrophone: Bool { self != .system }
    var usesSystemAudio: Bool { self != .microphone }
    static func from(microphone: Bool, system: Bool) -> AudioSource? {
        switch (microphone, system) {
        case (true, true): return .both
        case (true, false): return .microphone
        case (false, true): return .system
        case (false, false): return nil
        }
    }
}
enum ASRModel: String, Codable, CaseIterable, Identifiable {
    case small, large, best
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Fast · Qwen3-ASR 0.6B"
        case .large: return "Balanced · Qwen3-ASR 1.7B 8-bit"
        case .best: return "Best · Qwen3-ASR 1.7B full precision"
        }
    }
    var shortLabel: String {
        switch self {
        case .small: return "0.6B"
        case .large: return "1.7B · 8-bit"
        case .best: return "1.7B · BF16"
        }
    }
    /// Peak memory while transcribing, measured on Apple Silicon with 2 minutes of meeting audio.
    var memoryGB: Double {
        switch self {
        case .small: return 1.9
        case .large: return 3.5
        case .best: return 5.0
        }
    }
    /// Measured transcription speed, as a multiple of real time.
    var speed: Int {
        switch self {
        case .small: return 85
        case .large: return 40
        case .best: return 27
        }
    }
    static func recommended(forMemory bytes: UInt64) -> ASRModel {
        let gigabytes = Double(bytes) / 1_073_741_824
        return gigabytes < 12 ? .small : gigabytes < 16 ? .large : .best
    }
    var size: String {
        switch self {
        case .small: return "1 GB"
        case .large: return "2.3 GB"
        case .best: return "4.1 GB"
        }
    }
}
struct TranscriptSegment: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var start: Double
    var end: Double
    var text: String
    var source: String
    var language: String?
    /// Microphone audio is the person recording; Mac audio is everyone else on the call.
    var speaker: String {
        switch source {
        case "microphone": return "You"
        case "system": return "Colleagues"
        default: return "Speaker"
        }
    }
    var isRightToLeft: Bool {
        if let language, ["Arabic", "Hebrew", "Persian", "Urdu"].contains(language) { return true }
        return text.unicodeScalars.first { $0.properties.isAlphabetic }.map { (0x0590...0x08FF).contains($0.value) } ?? false
    }
}
struct Meeting: Codable, Identifiable {
    var id = UUID()
    var title: String
    var createdAt = Date()
    var duration: Double = 0
    var status: MeetingStatus = .recording
    var source: AudioSource = .both
    var model: ASRModel = .best
    var segments: [TranscriptSegment] = []
    var notes = ""
    var summary = ""
    var error: String?
    var captureError: String?
    var audioDeleted = false
    var notesStale: Bool?
    /// `false` for automatically named meetings, which AI analysis may rename. Legacy meetings (`nil`) keep their names.
    var titleEdited: Bool?
    var analysisTemplate: String?
    var analysisModel: String?
    var analyzedAt: Date?

    static func automaticTitle(_ date: Date = Date()) -> String {
        "Meeting · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
    /// Stores AI notes; renames only meetings the user never named themselves.
    mutating func apply(_ analysis: MeetingAnalysis, template: String, model: String, at date: Date = Date()) {
        summary = analysis.notes
        notesStale = false
        analysisTemplate = template
        analysisModel = model
        analyzedAt = date
        if titleEdited == false, let title = analysis.title { self.title = title }
    }
    mutating func replaceTranscript(_ replacement: [TranscriptSegment]) {
        if replacement != segments { notesStale = !summary.isEmpty }
        segments = replacement
    }
    var transcript: String { segments.map { "[\(Self.timestamp($0.start))] \($0.speaker): \($0.text)" }.joined(separator: "\n") }
    var shareableNotes: String {
        (notesStale == true ? "> These notes belong to an earlier transcription.\n\n" : "") + summary
    }
    var markdown: String {
        var sections = ["# \(title)", "\(createdAt.formatted(date: .complete, time: .shortened)) · \(Self.timestamp(duration))"]
        if !summary.isEmpty { sections += ["## Meeting notes", shareableNotes] }
        if !notes.isEmpty { sections += ["## My notes", notes] }
        sections += ["## Transcript", transcript]
        return sections.joined(separator: "\n\n") + "\n"
    }
    func audioExpired(after days: Int, now: Date) -> Bool {
        days > 0 && status == .ready && captureError == nil && !audioDeleted && now.timeIntervalSince(createdAt) >= Double(days) * 86400
    }
    static func timestamp(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60) : String(format: "%02d:%02d", value / 60, value % 60)
    }
}
struct AnalysisTemplate: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var prompt: String
    static let defaults: [AnalysisTemplate] = [
        .init(name: "Meeting notes", prompt: "Summarize what was discussed, the decisions that were made, and what happens next. Be concise and concrete."),
        .init(name: "Sales call", prompt: "Focus on the prospect: needs, pain points, objections, budget, timeline, decision makers, buying signals, risks, and the agreed next steps."),
        .init(name: "Technical sync", prompt: "Focus on technical decisions, architecture trade-offs, risks, blockers, estimates, and who owns each engineering task."),
        .init(name: "One-on-one", prompt: "Focus on feedback given and received, goals, blockers, wellbeing, and the commitments each person made.")
    ]
}
struct Preferences: Codable, Equatable {
    var model: ASRModel = .best
    var source: AudioSource = .both
    var retentionDays = 7
    var launchAtLogin = false
    var appearance = "system"
    /// Languages people speak in meetings. Empty: detect any of Qwen3-ASR's 30 languages.
    var languages: [String] = []
    var vocabulary = ""
    var openRouterModel = "google/gemini-2.5-flash"
    var templates = AnalysisTemplate.defaults
    var templateID: UUID?

    var template: AnalysisTemplate { templates.first { $0.id == templateID } ?? templates.first ?? AnalysisTemplate.defaults[0] }
    static let supportedLanguages = ["English", "Arabic", "French", "Spanish", "German", "Italian", "Portuguese", "Dutch", "Turkish", "Russian", "Hindi", "Persian", "Chinese", "Cantonese", "Japanese", "Korean", "Indonesian", "Malay", "Thai", "Vietnamese", "Filipino", "Swedish", "Danish", "Finnish", "Polish", "Czech", "Greek", "Romanian", "Hungarian", "Macedonian"]

    private enum LegacyKeys: String, CodingKey { case language }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Preferences()
        model = (try? values.decodeIfPresent(ASRModel.self, forKey: .model)) ?? defaults.model
        source = (try? values.decodeIfPresent(AudioSource.self, forKey: .source)) ?? defaults.source
        retentionDays = (try? values.decodeIfPresent(Int.self, forKey: .retentionDays)) ?? defaults.retentionDays
        launchAtLogin = (try? values.decodeIfPresent(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        appearance = (try? values.decodeIfPresent(String.self, forKey: .appearance)) ?? defaults.appearance
        let legacy = (try? decoder.container(keyedBy: LegacyKeys.self).decodeIfPresent(String.self, forKey: .language)) ?? nil
        languages = (try? values.decodeIfPresent([String].self, forKey: .languages)) ?? legacy.flatMap { Self.supportedLanguages.contains($0) ? [$0] : nil } ?? []
        vocabulary = (try? values.decodeIfPresent(String.self, forKey: .vocabulary)) ?? defaults.vocabulary
        openRouterModel = (try? values.decodeIfPresent(String.self, forKey: .openRouterModel)) ?? defaults.openRouterModel
        templates = (try? values.decodeIfPresent([AnalysisTemplate].self, forKey: .templates)).flatMap { $0.isEmpty ? nil : $0 } ?? defaults.templates
        templateID = try? values.decodeIfPresent(UUID.self, forKey: .templateID)
    }
}
