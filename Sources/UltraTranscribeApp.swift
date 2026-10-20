import AppKit
import SwiftUI
import UserNotifications

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
final class ApplicationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSToolbarDelegate {
    let state: AppState
    private var statusBar: StatusBarController?
    private var library: NSWindow?
    private var settings: NSWindow?
    private var setup: NSWindow?
    /// One per window, so a closed or hidden window stops drawing live audio while keeping its views for reopening.
    private var visibility: [ObjectIdentifier: Visibility] = [:]
    private var quitting = false
    private static let sidebarItem = NSToolbarItem.Identifier("UltraTranscribe.ToggleSidebar")

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
        state.showSetup = { [weak self] in self?.showSetup() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        state.savePreferences()
        let controller = StatusBarController(state: state)
        statusBar = controller
        let event = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = event?.eventID == kAEOpenApplication && event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if Notifier.available { UNUserNotificationCenter.current().delegate = self }
        state.updater.onFound = { release in
            let version = release.version?.description ?? release.tag
            guard UserDefaults.standard.string(forKey: "notifiedVersion") != version else { return }
            UserDefaults.standard.set(version, forKey: "notifiedVersion")
            Notifier.post(id: "update-\(version)", title: "Ultra Transcribe \(version) is available", body: "Open Settings → Credits to install it.", info: ["update": version])
        }
        state.updater.scheduleChecks { [weak state] in state?.preferences.checkForUpdates ?? false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak state] in state?.compactLibrary() }
        if launchedAtLogin { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            if self.state.preferences.setupDone { controller.showPanel() } else { self.showSetup() }
        }
    }
    func showSetup() {
        statusBar?.closePanel()
        if let setup { setup.close(); visibility[ObjectIdentifier(setup)] = nil }
        let window = makeWindow(title: "Welcome to Ultra Transcribe", size: NSSize(width: 580, height: 560), autosave: "Setup", root: SetupView(state: state) { [weak self] in
            self?.setup?.close()
            self?.statusBar?.showPanel()
        })
        window.styleMask.remove(.resizable)
        setup = window
        present(window)
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let meeting = (response.notification.request.content.userInfo["meeting"] as? String).flatMap(UUID.init(uuidString:))
        let update = response.notification.request.content.userInfo["update"] != nil
        Task { @MainActor in
            if let meeting { self.showLibrary(selecting: meeting) } else if update { self.showSettings(.credits) }
        }
        completionHandler()
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
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
        // Shown before ordering front, so the first frame already draws live content.
        visibility[ObjectIdentifier(window)]?.shown = true
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
        if autosave != "Setup" {
            let toolbar = NSToolbar(identifier: autosave)
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
        }
        let surface = Visibility()
        surface.follow(window)
        visibility[ObjectIdentifier(window)] = surface
        window.contentViewController = NSHostingController(rootView: SurfaceRoot(visibility: surface, content: root))
        window.setContentSize(size)
        window.center()
        window.setFrameAutosaveName(autosave)
        return window
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbar.identifier == "Library" ? [Self.sidebarItem, .flexibleSpace] : [.flexibleSpace]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard identifier == Self.sidebarItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "Toggle sidebar"
        item.toolTip = "Show or hide the sidebar (⌃⌘S)"
        item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")
        item.target = self
        item.action = #selector(toggleSidebar)
        return item
    }
    @objc private func toggleSidebar() {
        let defaults = UserDefaults.standard
        defaults.set(!defaults.bool(forKey: "sidebarCollapsed"), forKey: "sidebarCollapsed")
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateCancel } // already saving and quitting; that finishes on its own
        guard state.activeID != nil || state.isWorking || state.starting || state.analyzingID != nil else {
            guard state.operationTask != nil else { return .terminateNow }
            // Background work such as audio compression stops cleanly first, so no files are left half swapped.
            quitting = true
            Task {
                await state.prepareToQuit()
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
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
