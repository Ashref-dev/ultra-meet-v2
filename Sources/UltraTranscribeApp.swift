import AppKit
import SwiftUI

@main
struct UltraTranscribeApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    var body: some Scene {
        // A menu-bar agent: no Dock icon, no app switcher entry. Windows are opened on demand by the delegate.
        Settings { EmptyView() }
            .commands { AppCommands(state: delegate.state, delegate: delegate) }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    let state: AppState
    private var statusBar: StatusBarController?
    private var library: NSWindow?
    private var settings: NSWindow?
    private var quitting = false

    override init() {
        do { state = try AppState() }
        catch {
            let alert = NSAlert()
            alert.messageText = "Ultra Transcribe could not open its local library"
            alert.informativeText = "\(error.localizedDescription)\nNo existing data has been changed."
            alert.runModal()
            exit(1)
        }
        super.init()
        state.showMeeting = { [weak self] id in self?.showLibrary(selecting: id) }
        state.showSettings = { [weak self] pane in self?.showSettings(pane) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.savePreferences()
        let controller = StatusBarController(state: state)
        statusBar = controller
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if !launchedAtLogin { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { controller.showPanel() } }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { statusBar?.showPanel() }
        return true
    }
    func showLibrary(selecting id: UUID? = nil) {
        if let id { state.selectedID = id }
        statusBar?.closePanel()
        let window = library ?? makeWindow(title: "Ultra Transcribe", size: NSSize(width: 1060, height: 720), autosave: "Library", root: LibraryView(state: state))
        library = window
        present(window)
    }
    func showSettings(_ pane: SettingsPane) {
        state.settingsPane = pane
        statusBar?.closePanel()
        let window = settings ?? makeWindow(title: "Settings", size: NSSize(width: 780, height: 580), autosave: "Settings", root: SettingsView(state: state))
        settings = window
        present(window)
    }
    private func present(_ window: NSWindow) {
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        DispatchQueue.main.async { window.makeFirstResponder(nil) }
    }
    private func makeWindow(title: String, size: NSSize, autosave: String, root: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(size)
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting, state.activeID != nil || state.isWorking || state.starting || state.analyzingID != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = state.activeID != nil ? "A meeting is still recording" : "A meeting is still being processed"
        alert.informativeText = "Quitting stops it. Audio and finished transcripts stay on this Mac, so you can transcribe again later."
        alert.addButton(withTitle: "Keep Working")
        alert.addButton(withTitle: "Save & Quit")
        NSApp.activate()
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        quitting = true
        Task {
            await state.prepareToQuit()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
