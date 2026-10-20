import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var deleteID: UUID?
    @State private var dropTargeted = false
    @AppStorage("sidebarCollapsed") private var collapsed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A sized image preserves the circle and colors inside AppKit's native swipe action.
    private static let trashActionImage: NSImage = {
        let size = Theme.swipeActionSize
        let glyph = NSImage(systemSymbolName: "trash", accessibilityDescription: "Move to Trash")?
            .withSymbolConfiguration(.init(paletteColors: [.white]))
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor(Theme.destructive).setFill()
            NSBezierPath(ovalIn: rect).fill()
            glyph?.draw(in: rect.insetBy(dx: size * 0.28, dy: size * 0.24))
            return true
        }
    }()
    /// A meeting that matches the search and, when its title doesn't, the first transcript line that does, shown under
    /// the meeting so results explain themselves.
    struct SearchResult: Identifiable {
        let meeting: Meeting
        let line: TranscriptSegment?
        var id: UUID { meeting.id }
    }
    /// Search ignores case, accents and Arabic spelling variants (see `searchFolded`). Folding transcripts is the
    /// expensive part, so the query is folded once and each meeting is read once.
    var results: [SearchResult] {
        let query = state.search.trimmingCharacters(in: .whitespaces).searchFolded
        guard !query.isEmpty else { return state.meetings.map { SearchResult(meeting: $0, line: nil) } }
        return state.meetings.compactMap { meeting in
            if meeting.title.searchFolded.contains(query) { return SearchResult(meeting: meeting, line: nil) }
            let line = meeting.segments.first { $0.text.searchFolded.contains(query) }
            guard line != nil || meeting.summary.searchFolded.contains(query) || meeting.notes.searchFolded.contains(query) else { return nil }
            return SearchResult(meeting: meeting, line: line)
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            if !collapsed {
                sidebar.frame(width: 272).floatingSidebar(Theme.paper)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            VStack(spacing: 0) {
                if let error = state.error {
                    InlineHint(error: error, openSettings: state.showSettings) { state.error = nil }
                        .padding(.horizontal, 24).padding(.top, 16)
                        .transition(.opacity)
                }
                Group {
                    if let meeting = state.selected { MeetingDetail(state: state, meeting: meeting) } else { emptyState }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(reduceMotion ? nil : Theme.feedback, value: state.error)
        }
        .background(Theme.paper.ignoresSafeArea())
        .overlay { if dropTargeted { dropHint.transition(.opacity) } }
        .animation(reduceMotion ? nil : Theme.feedback, value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            guard state.canStart, let url = urls.first(where: { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) == true }) else { return false }
            state.importAudio(from: url)
            return true
        } isTargeted: { dropTargeted = $0 && state.canStart }
        .background(KeyMonitor { key in
            switch key {
            case KeyMonitor.up, KeyMonitor.down: return select(step: key == KeyMonitor.down ? 1 : -1)
            case KeyMonitor.delete, KeyMonitor.forwardDelete:
                guard let id = state.selectedID, !state.isProtected(id) else { return false }
                deleteID = id
                return true
            default: return false
            }
        })
        .animation(reduceMotion ? nil : Theme.selection, value: collapsed)
        .frame(minWidth: collapsed ? 560 : 820, minHeight: 560)
        .confirmationDialog("Move this meeting and its audio to the Trash?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Move to Trash", role: .destructive) { if let id = deleteID { state.deleteMeeting(id) }; deleteID = nil }
                .disabled(deleteID.map { state.isProtected($0) } ?? true)
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: { Text("You can restore it from the Finder Trash until it’s emptied.") }
    }
    var sidebar: some View {
        let results = self.results
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoMark(size: 13)
                Text("Ultra Transcribe").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { state.showSettings(.general) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true, square: true)).help("Settings (⌘,)").accessibilityLabel("Settings")
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.top, 8).padding(.bottom, 16)
            Group {
                if let active = state.active {
                    Button { state.selectedID = active.id } label: {
                        HStack(spacing: 8) {
                            Circle().fill(state.recorder.paused ? Theme.secondary : Theme.orange).frame(width: 7, height: 7)
                            Text(state.recorder.paused ? "Paused" : "Recording")
                            Spacer()
                            ElapsedReader(clock: state.clock) { Text(Meeting.timestamp($0)) }.monospacedDigit()
                        }
                    }.buttonStyle(ControlStyle(expand: true))
                } else {
                    Button { state.startRecording() } label: {
                        RecordLabel(title: state.starting ? "Starting" : "Start recording", busy: state.starting) { Circle().fill(.white).frame(width: 7, height: 7) }
                    }.buttonStyle(ControlStyle(kind: .primary, expand: true)).disabled(!state.canStart)
                }
            }
            .padding(.horizontal, 12)
            SearchField(prompt: "Search meetings", text: $state.search, findShortcut: true)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 8)
            ScrollViewReader { proxy in
            List(results) { result in
                let meeting = result.meeting
                Button { state.selectedID = meeting.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        MeetingRow(state: state, meeting: meeting)
                        if let line = result.line {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(Theme.speakerColor(line.source)).frame(width: 5, height: 5)
                                Text(line.text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(2)
                                    .multilineTextAlignment(line.isRightToLeft ? .trailing : .leading)
                                    .frame(maxWidth: .infinity, alignment: line.isRightToLeft ? .trailing : .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 12)
                }
                .buttonStyle(RowStyle(selected: meeting.id == state.selectedID))
                .accessibilityAddTraits(meeting.id == state.selectedID ? .isSelected : [])
                .selectionDisabled()
                .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear.thinScrollbars())
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !state.isProtected(meeting.id) {
                        // The swipe requests confirmation; only the confirmed action is destructive.
                        Button { deleteID = meeting.id } label: {
                            Label { Text("Trash") } icon: {
                                Image(nsImage: Self.trashActionImage).renderingMode(.original)
                            }
                        }
                        .tint(.clear)
                        .accessibilityLabel("Move to Trash")
                        .help("Move to Trash")
                    }
                }
                .contextMenu {
                    Button("Export Markdown…") { state.export(meeting) }
                    Button("Show in Finder") { NSWorkspace.shared.open(state.library.folder(meeting.id)) }
                    Divider()
                    Button("Move to Trash…", role: .destructive) { deleteID = meeting.id }.disabled(state.isProtected(meeting.id))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .onChange(of: state.selectedID) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : Theme.selection) { proxy.scrollTo(id) }
            }
            .overlay {
                if results.isEmpty && !state.meetings.isEmpty { Text("No matches").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
            }
        }
    }
    /// Moves the selection through the visible meetings with the arrow keys.
    func select(step: Int) -> Bool {
        let results = self.results
        guard !results.isEmpty else { return false }
        let current = results.firstIndex { $0.id == state.selectedID }
        let next = current.map { min(max($0 + step, 0), results.count - 1) } ?? 0
        state.selectedID = results[next].id
        return true
    }
    var dropHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.plus").font(.system(size: 28, weight: .medium)).foregroundStyle(Theme.orange)
            Text("Drop audio to transcribe it").font(.system(size: 15, weight: .semibold))
            MonoLabel("WAV, M4A, MP3, AIFF, FLAC")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.opacity(0.85))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 5])).padding(8))
        .allowsHitTesting(false)
    }
    var emptyState: some View {
        VStack(spacing: 16) {
            DotWaveform(meter: state.recorder.levels).frame(width: 320, height: 64)
            Text("Nothing recorded yet").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
            Text("Start from here or from the menu bar. Meetings name themselves.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Button { state.startRecording() } label: { Text("Start recording") }.buttonStyle(ControlStyle(kind: .primary)).disabled(!state.canStart)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
    }
}
