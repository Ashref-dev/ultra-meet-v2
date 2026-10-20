import Foundation

struct LibrarySnapshot { let meetings: [Meeting]; let warnings: [String] }

extension MeetingLibrary {
    func recover(_ meeting: Meeting) -> Meeting {
        var recovered = meeting
        let directory = folder(meeting.id)
        let complete = directory.appendingPathComponent("transcript.json")
        let partial = directory.appendingPathComponent("transcript.partial.json")
        // Only output newer than the meeting itself belongs to the run that was interrupted. An older transcript.json
        // is from an earlier run, and adopting it would undo corrections made since.
        let saved = modified(directory.appendingPathComponent("meeting.json"))
        if modified(complete) > saved, let data = try? Data(contentsOf: complete), let transcript = try? JSONDecoder().decode(WorkerTranscript.self, from: data) {
            recovered.replaceTranscript(transcript.segments)
        } else if recovered.segments.isEmpty, let data = try? Data(contentsOf: partial), let transcript = try? JSONDecoder().decode(WorkerTranscript.self, from: data) {
            recovered.segments = transcript.segments
        }
        if meeting.status == .recording { recovered.captureError = "Recording was interrupted when the app closed." }
        if meeting.status == .importing { recovered.captureError = "Audio import was interrupted before it finished." }
        recovered.status = .interrupted
        recovered.error = "The app closed before this meeting finished. Retained audio and completed processing checkpoints have been recovered. You can transcribe the retained audio again."
        return recovered
    }
    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
