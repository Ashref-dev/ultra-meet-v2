import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var deleteID: UUID?
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
    /// Search ignores case, accents and Arabic spelling variants (see `searchFolded`).
    var query: String { state.search.trimmingCharacters(in: .whitespaces).searchFolded }
    var filtered: [Meeting] {
        guard !query.isEmpty else { return state.meetings }
        return state.meetings.filter { meeting in
            [meeting.title, meeting.summary, meeting.notes].contains { $0.searchFolded.contains(query) } || meeting.segments.contains { $0.text.searchFolded.contains(query) }
        }
    }
    /// The first transcript line that matches, shown under the meeting so results explain themselves.
    func snippet(_ meeting: Meeting) -> TranscriptSegment? {
        guard !query.isEmpty, !meeting.title.searchFolded.contains(query) else { return nil }
        return meeting.segments.first { $0.text.searchFolded.contains(query) }
    }
    var body: some View {
        HStack(spacing: 0) {
            if !collapsed {
                sidebar.frame(width: 280).sidebarSurface()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Group {
                if let meeting = state.selected { MeetingDetail(state: state, meeting: meeting) } else { emptyState }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
        }
        .animation(reduceMotion ? nil : Theme.selection, value: collapsed)
        .tint(Theme.orange)
        .frame(minWidth: collapsed ? 560 : 820, minHeight: 560)
        .alert("Something needs your attention", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .confirmationDialog("Move this meeting and its audio to the Trash?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Move to Trash", role: .destructive) { if let id = deleteID { state.deleteMeeting(id) }; deleteID = nil }
                .disabled(deleteID.map { state.isProtected($0) } ?? true)
            Button("Cancel", role: .cancel) { deleteID = nil }
        } message: { Text("You can restore it from the Finder Trash until it’s emptied.") }
    }
    var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                LogoMark(size: 14)
                Text("Ultra Transcribe").font(.system(size: 14, weight: .semibold))
                Spacer()
                Button { state.showSettings(.general) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true)).help("Settings (⌘,)").accessibilityLabel("Settings")
            }
            .padding(.leading, 18).padding(.trailing, 12).padding(.top, 16).padding(.bottom, 20)
            GlassControls {
                if let active = state.active {
                    Button { state.selectedID = active.id } label: {
                        HStack(spacing: 8) {
                            Circle().fill(state.recorder.paused ? Theme.secondary : Theme.orange).frame(width: 7, height: 7)
                            Text(state.recorder.paused ? "Paused" : "Recording")
                            Spacer()
                            Text(Meeting.timestamp(state.elapsed)).monospacedDigit()
                        }
                    }.buttonStyle(ControlStyle(expand: true))
                } else {
                    Button { state.startRecording() } label: {
                        HStack(spacing: 8) { Circle().fill(.white).frame(width: 7, height: 7); Text(state.starting ? "Starting" : "Start recording") }
                    }.buttonStyle(ControlStyle(kind: .primary, expand: true)).disabled(!state.canStart)
                }
            }
            .padding(.horizontal, 14)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                TextField("Search meetings", text: $state.search).textFieldStyle(.plain).font(.system(size: 12.5))
                if !state.search.isEmpty {
                    Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 12).frame(height: Theme.controlHeight)
            .background(Theme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.line.opacity(0.5)))
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            List(filtered) { meeting in
                Button { state.selectedID = meeting.id } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        MeetingRow(state: state, meeting: meeting)
                        if let line = snippet(meeting) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Circle().fill(Theme.speakerColor(line.source)).frame(width: 5, height: 5)
                                Text(line.text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(2)
                                    .multilineTextAlignment(line.isRightToLeft ? .trailing : .leading)
                                    .frame(maxWidth: .infinity, alignment: line.isRightToLeft ? .trailing : .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 11)
                }
                .buttonStyle(RowStyle(selected: meeting.id == state.selectedID))
                .accessibilityAddTraits(meeting.id == state.selectedID ? .isSelected : [])
                .selectionDisabled()
                .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
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
            .overlay {
                if filtered.isEmpty && !state.meetings.isEmpty { Text("No matches").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
        }
    }
    var emptyState: some View {
        VStack(spacing: 18) {
            DotWaveform(meter: state.recorder.levels).frame(width: 320, height: 64)
            Text("Nothing recorded yet").font(.system(size: 22, weight: .semibold)).tracking(-0.4)
            Text("Start from here or from the menu bar. Meetings name themselves.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            Button { state.startRecording() } label: { Text("Start recording") }.buttonStyle(ControlStyle(kind: .primary)).disabled(!state.canStart)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
    }
}
