import AppKit
import Foundation
import Security

/// `MAJOR.MINOR.PATCH` with an optional pre-release suffix, as in the GitHub tags (`v0.6.0`).
struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = (trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed).split(separator: "-", maxSplits: 1)
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        let values = numbers.compactMap { $0 } + Array(repeating: 0, count: 3 - numbers.count)
        (major, minor, patch) = (values[0], values[1], values[2])
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    var description: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) { return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch) }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }
}

struct Release: Decodable, Equatable {
    struct Asset: Decodable, Equatable {
        let name: String
        let url: URL
        let size: Int
        enum CodingKeys: String, CodingKey { case name, size, url = "browser_download_url" }
    }
    let tag: String
    let name: String?
    let notes: String?
    let page: URL
    let draft: Bool
    let assets: [Asset]
    enum CodingKeys: String, CodingKey { case tag = "tag_name", name, notes = "body", page = "html_url", draft, assets }

    var version: SemanticVersion? { SemanticVersion(tag) }
    var archive: Asset? { assets.first { $0.name.lowercased().hasSuffix(".zip") } }
    /// The newest published release above `current`. Releases marked pre-release on GitHub count: every 0.x
    /// release is one.
    static func newest(_ releases: [Release], above current: SemanticVersion) -> Release? {
        releases.filter { !$0.draft && ($0.version.map { $0 > current } ?? false) }.max { ($0.version ?? current) < ($1.version ?? current) }
    }
}

enum UpdateState: Equatable {
    case idle
    case checking
    case current(Date)
    case available(Release)
    case installing(String)
    case failed(String)
}

/// Update management: reads the public GitHub release list (nothing about the person is sent), and installs a
/// release in place after checking it is this app, signed by the same developer team.
@MainActor
final class Updater: ObservableObject {
    static let releasesAPI = URL(string: "https://api.github.com/repos/Ashref-dev/ultra-meet-v2/releases?per_page=20")!
    static let releasesPage = URL(string: "https://github.com/Ashref-dev/ultra-meet-v2/releases")!
    @Published private(set) var state = UpdateState.idle
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    var onFound: ((Release) -> Void)?
    private var timer: Timer?
    private let session = URLSession(configuration: .ephemeral)

    var available: Release? { if case .available(let release) = state { return release }; return nil }
    var busy: Bool {
        switch state {
        case .checking, .installing: return true
        default: return false
        }
    }

    /// Checks once a day while the app runs; the first check waits a minute after launch.
    func scheduleChecks(enabled: @escaping @MainActor () -> Bool) {
        timer?.invalidate()
        let tick = { [weak self] in
            guard let self, enabled() else { return }
            let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
            if Date().timeIntervalSince(last) > 86_400 { Task { await self.check(automatic: true) } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { tick() } }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
    }

    func check(automatic: Bool = false) async {
        guard !busy, let current = version.flatMap(SemanticVersion.init) else {
            if !automatic && version.flatMap(SemanticVersion.init) == nil { state = .failed("This development build has no version to compare.") }
            return
        }
        state = .checking
        do {
            var request = URLRequest(url: Self.releasesAPI, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw AppError.message(status == 403 ? "GitHub is limiting requests right now. Try again in an hour." : "GitHub didn’t answer (\(status)). Try again later.") }
            let releases = try JSONDecoder().decode([Release].self, from: data)
            UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
            if let newest = Release.newest(releases, above: current) {
                state = .available(newest)
                onFound?(newest)
            } else {
                state = .current(Date())
            }
        } catch {
            state = automatic ? .idle : .failed(error is URLError ? "Couldn’t reach GitHub. Check your internet connection." : error.localizedDescription)
        }
    }

    /// Downloads the release archive, verifies it, moves the running copy to the Trash, puts the new one in its
    /// place and relaunches. Anything unexpected stops before the current copy is touched.
    func install(_ release: Release, busy isBusy: @escaping @MainActor () -> Bool) async {
        guard let archive = release.archive else { NSWorkspace.shared.open(release.page); return }
        state = .installing("Downloading \(release.version?.description ?? release.tag)…")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UltraTranscribeUpdate-\(UUID().uuidString)")
        do {
            let (download, response) = try await session.download(from: archive.url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError.message("The download didn’t complete.") }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            state = .installing("Checking the signature…")
            try await Self.run("/usr/bin/ditto", ["-x", "-k", download.path, folder.path])
            guard let app = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                throw AppError.message("The download doesn’t contain the app.")
            }
            let target = Bundle.main.bundleURL
            try UpdateInstaller.verify(app, replacing: target)
            guard !isBusy() else { throw AppError.message("A meeting is recording or being processed. Install when it’s done.") }
            state = .installing("Installing…")
            try UpdateInstaller.replace(target, with: app)
            try Self.relaunch(target)
        } catch {
            state = .failed("The update couldn’t be installed. \(error.localizedDescription) You can download it from GitHub instead.")
        }
        try? FileManager.default.removeItem(at: folder)
    }

    private static func run(_ executable: String, _ arguments: [String]) async throws {
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            task.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw AppError.message("The archive couldn’t be opened (\(status)).") }
    }

    /// Opens the new copy once this process has really exited, however long quitting takes.
    private static func relaunch(_ app: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"", app.path, String(ProcessInfo.processInfo.processIdentifier)]
        try task.run()
        NSApp.terminate(nil)
    }
}

enum UpdateInstaller {
    /// The candidate must be this app (same bundle identifier), validly signed by the same developer team, and newer.
    static func verify(_ candidate: URL, replacing current: URL) throws {
        guard let new = Bundle(url: candidate), let installed = Bundle(url: current), new.bundleIdentifier == installed.bundleIdentifier, new.bundleIdentifier != nil else {
            throw AppError.message("The download isn’t Ultra Transcribe.")
        }
        guard let team = teamIdentifier(current) else { throw AppError.message("This copy isn’t signed by a developer team, so the download can’t be verified.") }
        guard teamIdentifier(candidate) == team, isValid(candidate) else { throw AppError.message("The download’s signature doesn’t match this app.") }
        guard let newVersion = (new.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(SemanticVersion.init),
              let oldVersion = (installed.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(SemanticVersion.init),
              newVersion > oldVersion else { throw AppError.message("The download isn’t newer than this version.") }
    }

    /// Copies the new app next to the current one first, so the swap is a rename on the same volume. Then the
    /// current copy goes to the Trash (never deleted) and the new one takes its path. If that fails, the old copy
    /// is put back, or the error says where it is.
    static func replace(_ target: URL, with app: URL) throws {
        let files = FileManager.default
        let staged = target.deletingLastPathComponent().appendingPathComponent(".\(target.deletingPathExtension().lastPathComponent)-update-\(UUID().uuidString).app")
        try files.moveItem(at: app, to: staged)
        var trashed: NSURL?
        do { try files.trashItem(at: target, resultingItemURL: &trashed) }
        catch { try? files.removeItem(at: staged); throw error }
        do { try files.moveItem(at: staged, to: target) }
        catch {
            guard let old = trashed as URL? else { throw error }
            do { try files.moveItem(at: old, to: target) }
            catch { throw AppError.message("The previous version is in the Trash at \(old.path). Move it back to \(target.deletingLastPathComponent().path) to keep using it.") }
            try? files.removeItem(at: staged)
            throw error
        }
    }

    static func teamIdentifier(_ url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess else { return nil }
        return (information as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    static func isValid(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode), nil) == errSecSuccess
    }
}
