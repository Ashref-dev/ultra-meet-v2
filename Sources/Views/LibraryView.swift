import AppKit
import SwiftUI

struct LibraryView: View {
    @ObservedObject var state: AppState
    @State private var deleteID: UUID?
    @AppStorage("sidebarCollapsed") private var collapsed = false
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
                sidebar.frame(width: 270).background(Theme.background.ignoresSafeArea())
                    .transition(.move(edge: .leading).combined(with: .opacity))
                Divider().ignoresSafeArea()
            }
            Group {
                if let meeting = state.selected { MeetingDetail(state: state, meeting: meeting) } else { emptyState }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper.ignoresSafeArea())
        }
        .overlay(alignment: .topLeading) {
            Button { withAnimation(Theme.selection) { collapsed.toggle() } } label: {
                Image(systemName: "sidebar.left").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(ControlStyle(kind: .quiet, compact: true))
            .help(collapsed ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)")
            .accessibilityLabel(collapsed ? "Show sidebar" : "Hide sidebar")
            .padding(.leading, 76).padding(.top, -24)
        }
        .tint(Theme.orange)
        .frame(minWidth: collapsed ? 560 : 820, minHeight: 560)
        .alert("Something needs your attention", isPresented: Binding(get: { state.error != nil }, set: { if !$0 { state.error = nil } })) {
            Button("OK") { state.error = nil }
        } message: { Text(state.error ?? "") }
        .confirmationDialog("Move this meeting and its audio to the Trash?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
            Button("Move to Trash", role: .destructive) { if let id = deleteID { state.deleteMeeting(id) }; deleteID = nil }
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
            .padding(.leading, 18).padding(.trailing, 10).padding(.top, 6).padding(.bottom, 14)
            Group {
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
            .padding(.horizontal, 10).frame(height: 30)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.line))
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 8)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { meeting in
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
                            .padding(.horizontal, 10).padding(.vertical, 9)
                        }
                        .buttonStyle(RowStyle(selected: meeting.id == state.selectedID))
                        .accessibilityAddTraits(meeting.id == state.selectedID ? .isSelected : [])
                        .contextMenu {
                            Button("Export Markdown…") { state.export(meeting) }
                            Button("Show in Finder") { NSWorkspace.shared.open(state.library.folder(meeting.id)) }
                            Divider()
                            Button("Move to Trash…", role: .destructive) { deleteID = meeting.id }.disabled(state.isProtected(meeting.id))
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
            .overlay {
                if filtered.isEmpty && !state.meetings.isEmpty { Text("No matches").font(.system(size: 12)).foregroundStyle(Theme.secondary) }
            }
        }
        .background(Theme.background)
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
