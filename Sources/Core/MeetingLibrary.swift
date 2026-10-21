import Foundation

struct MeetingLibrary {
    let root: URL
    /// The real library moves deleted audio to the Trash; tests, which use a temporary root, delete it directly.
    private let usesTrash: Bool
    init(root: URL? = nil) throws {
        usesTrash = root == nil
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UltraTranscribe", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.root.path)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Meetings"), withIntermediateDirectories: true)
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent("Meetings/\(id.uuidString)") }
    /// Setup's microphone and Mac audio checks record here, inside the private library, never in shared temp space.
    var scratch: URL { root.appendingPathComponent("Scratch", isDirectory: true) }
    /// Check recordings left by a crash or force quit are deleted at launch.
    func clearScratch() {
        try? FileManager.default.removeItem(at: scratch)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func save(_ meeting: Meeting) throws {
        let directory = folder(meeting.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meeting).write(to: directory.appendingPathComponent("meeting.json"), options: .atomic)
    }
    func load() throws -> [Meeting] {
        try snapshot().meetings
    }
    func snapshot() throws -> LibrarySnapshot {
        let directories = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Meetings"), includingPropertiesForKeys: nil)
        var meetings: [Meeting] = []
        var warnings: [String] = []
        for directory in directories {
            let path = directory.appendingPathComponent("meeting.json")
            guard FileManager.default.fileExists(atPath: path.path) else { continue }
            do {
                let meeting = try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: path))
                guard meeting.id.uuidString == directory.lastPathComponent else { throw AppError.message("The meeting ID does not match its storage folder.") }
                meetings.append(meeting)
            }
            catch { warnings.append("A meeting could not be read. Its folder is untouched: \(directory.path). \(error.localizedDescription)") }
        }
        return LibrarySnapshot(meetings: meetings.sorted { $0.createdAt > $1.createdAt }, warnings: warnings)
    }
    static let audioExtensions: Set<String> = ["wav", "caf", "m4a", "mp3", "flac", "aiff", "ogg"]
    /// Moves a meeting's audio to the Trash, where it can be recovered; transcript and notes stay.
    func removeAudio(_ id: UUID) throws {
        for file in try FileManager.default.contentsOfDirectory(at: folder(id), includingPropertiesForKeys: nil) where Self.audioExtensions.contains(file.pathExtension.lowercased()) {
            try discard(file)
        }
    }
    /// Moves a file the user may want back to the Trash; test libraries delete it.
    func discard(_ url: URL) throws {
        if usesTrash { try FileManager.default.trashItem(at: url, resultingItemURL: nil) } else { try FileManager.default.removeItem(at: url) }
    }
    func hasUncompressedAudio(_ id: UUID) -> Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder(id).path)) ?? []).contains { ["wav", "caf", "aiff"].contains(($0 as NSString).pathExtension.lowercased()) }
    }
    func savePreferences(_ preferences: Preferences) throws {
        try JSONEncoder().encode(preferences).write(to: root.appendingPathComponent("preferences.json"), options: .atomic)
    }
    func loadPreferences() throws -> Preferences {
        let url = root.appendingPathComponent("preferences.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return Preferences() }
        return try JSONDecoder().decode(Preferences.self, from: Data(contentsOf: url))
    }
}
