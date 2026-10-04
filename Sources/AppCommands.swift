import AppKit
import SwiftUI

struct AppCommands: Commands {
    @ObservedObject var state: AppState
    let delegate: ApplicationDelegate
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { delegate.showSettings(state.settingsPane) }.keyboardShortcut(",")
        }
        CommandGroup(replacing: .newItem) {
            Button("Start Recording") { state.startRecording() }.keyboardShortcut("n").disabled(!state.canStart)
            Button("Import Audio…") { state.importAudio() }.keyboardShortcut("o").disabled(!state.canStart)
            Button("Meeting Library") { delegate.showLibrary() }.keyboardShortcut("l")
        }
        CommandMenu("Recording") {
            Button(state.recorder.paused ? "Resume Recording" : "Pause Recording") { state.togglePause() }
                .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(state.activeID == nil || state.stopping)
            Button("Stop & Transcribe") { state.stopRecording() }
                .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(state.activeID == nil || state.stopping)
        }
        CommandGroup(replacing: .help) {
            Button("Ultra Transcribe Help") {
                if let help = Bundle.module.url(forResource: "Help", withExtension: "md", subdirectory: "Resources") { NSWorkspace.shared.open(help) }
            }
        }
    }
}
