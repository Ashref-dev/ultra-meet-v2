import Foundation

struct MeetingLibrary {
    let root: URL
    init(root: URL? = nil) throws {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("UltraTranscribe", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: self.root.path)
        try FileManager.default.createDirectory(at: self.root.appendingPathComponent("Meetings"), withIntermediateDirectories: true)
    }
    func folder(_ id: UUID) -> URL { root.appendingPathComponent("Meetings/\(id.uuidString)") }
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
    func removeAudio(_ id: UUID) throws {
        let directory = folder(id)
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) where ["wav", "caf", "m4a", "mp3", "flac", "aiff", "ogg"].contains(file.pathExtension.lowercased()) {
            try FileManager.default.removeItem(at: file)
        }
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
