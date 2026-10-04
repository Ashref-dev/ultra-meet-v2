import AppKit
import Combine
import SwiftUI

/// Native status item: left-click opens the recorder panel, right-click (or Control-click) opens quick actions.
@MainActor
final class StatusBarController: NSObject {
    private let state: AppState
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var subscriptions = Set<AnyCancellable>()
    private var appearance = ""
    private var ripple: Timer?
    private var phase = 0.0

    init(state: AppState) {
        self.state = state
        super.init()
        item.autosaveName = "UltraTranscribe"
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("Ultra Transcribe")
        }
        let host = NSHostingController(rootView: MenuBarPanel(state: state))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refresh() }
            .store(in: &subscriptions)
        state.recorder.levels.$history
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        state.$activeID.removeDuplicates().dropFirst()
            .filter { $0 != nil }
            .sink { [weak self] _ in self?.getOutOfTheWay() }
            .store(in: &subscriptions)
        refresh()
    }

    func showPanel() {
        guard let button = item.button, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(nil)
    }
    func closePanel() { if popover.isShown { popover.performClose(nil) } }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            closePanel()
            item.menu = menu()
            item.button?.performClick(nil)
            item.menu = nil
        } else if popover.isShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    /// After one-click start, show "Recording" briefly, then hand focus back to the call.
    private func getOutOfTheWay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self, self.popover.isShown, self.state.activeID != nil else { return }
            self.closePanel()
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.hide(nil) }
        }
    }

    private func menu() -> NSMenu {
        let menu = NSMenu()
        let recording = state.activeID != nil
        let status = NSMenuItem(title: recording ? "\(state.recorder.paused ? "Paused" : "Recording") · \(Meeting.timestamp(state.elapsed))" : state.processingID != nil ? "Transcribing · \(Int(state.engine.fraction * 100))%" : "Ready to record", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        if recording {
            menu.addItem(entry(state.recorder.paused ? "Resume Recording" : "Pause Recording", symbol: state.recorder.paused ? "play.fill" : "pause.fill", enabled: !state.stopping) { [state] in state.togglePause() })
            menu.addItem(entry("Stop Recording", symbol: "stop.fill", enabled: !state.stopping) { [state] in state.stopRecording() })
        } else {
            menu.addItem(entry("Start Recording", symbol: "record.circle", enabled: state.canStart) { [state] in state.startRecording() })
        }
        if state.preferences.globalShortcut, let toggle = menu.items.last(where: { $0.title == "Start Recording" || $0.title == "Stop Recording" }) {
            toggle.keyEquivalent = "r"
            toggle.keyEquivalentModifierMask = [.control, .option, .command]
        }
        menu.addItem(.separator())
        menu.addItem(entry("Meeting Library…", symbol: "list.bullet.rectangle") { [state] in state.showMeeting(nil) })
        menu.addItem(entry("Settings…", symbol: "gearshape") { [state] in state.showSettings(.general) })
        if let release = state.updater.available {
            menu.addItem(entry("Update to \(release.version?.description ?? release.tag)…", symbol: "arrow.down.circle") { [state] in state.showSettings(.credits) })
        } else {
            menu.addItem(entry("Check for Updates…", symbol: nil) { [state] in
                state.showSettings(.credits)
                Task { await state.updater.check() }
            })
        }
        menu.addItem(.separator())
        menu.addItem(entry("Quit Ultra Transcribe", symbol: nil) { NSApp.terminate(nil) })
        return menu
    }
    private func entry(_ title: String, symbol: String?, enabled: Bool = true, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, action: action)
        item.isEnabled = enabled
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    /// The icon is the whole status: live dots while recording, a flat line when paused, a ripple while transcribing.
    private func refresh() {
        guard let button = item.button else { return }
        let recording = state.activeID != nil
        let paused = recording && state.recorder.paused
        let working = !recording && state.isWorking
        if working && ripple == nil {
            ripple = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.phase += 0.7; self?.refresh() }
            }
        } else if !working, let timer = ripple {
            timer.invalidate()
            ripple = nil
        }
        let progress = state.processingID != nil ? state.engine.fraction : 0
        let levels = recording && !paused ? columnLevels() : working ? (progress > 0.03 ? progressLevels(progress) : rippleLevels()) : nil
        let key = paused ? "paused" : levels.map { $0.map { String(Int($0 * 5)) }.joined() } ?? "idle"
        guard key != appearance else { return }
        appearance = key
        button.image = Self.icon(levels: levels, alpha: paused ? 0.4 : 1)
        button.setAccessibilityValue(recording ? (paused ? "Paused" : "Recording \(Meeting.timestamp(state.elapsed))") : working ? "Transcribing" : "Ready")
        button.toolTip = recording ? "\(paused ? "Paused" : "Recording") · \(Meeting.timestamp(state.elapsed))" : working ? "Transcribing \(Int(state.engine.fraction * 100))%" : "Ultra Transcribe"
    }

    /// Transcription progress: the logo's waveform fills in from left to right.
    private func progressLevels(_ fraction: Double) -> [Double] {
        LogoGlyph.heights.indices.map { Double($0) < fraction * Double(LogoGlyph.heights.count) ? Double(LogoGlyph.heights[$0]) / Double(LogoGlyph.rows) : 0 }
    }

    private func rippleLevels() -> [Double] {
        (0..<LogoGlyph.heights.count).map { 0.35 + 0.65 * max(0, sin(phase - Double($0) * 0.9)) }
    }

    /// The last few level samples, one per logo column, so the icon itself moves with the conversation.
    private func columnLevels() -> [Double] {
        let count = LogoGlyph.heights.count
        let samples = state.recorder.levels.history.suffix(count).map { Double(max($0.you, $0.colleagues)) }
        return samples.enumerated().map { index, level in
            let shape = Double(LogoGlyph.heights[index]) / Double(LogoGlyph.rows)
            return max(0.2, min(1, pow(level, 1.3) * 1.2 * (0.55 + shape * 0.45)))
        }
    }

    /// The logo as a template image: faint lattice, solid waveform. Recording swaps the waveform for live levels; paused fades it.
    private static func icon(levels: [Double]?, alpha: CGFloat = 1) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: true) { rect in
            for dot in LogoGlyph.dots(in: rect.insetBy(dx: 0.5, dy: 1), levels: levels) {
                NSColor.black.withAlphaComponent(dot.active ? alpha : 0.22).setFill()
                NSBezierPath(ovalIn: dot.rect).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Ultra Transcribe"
        return image
    }
}

/// NSMenuItem that runs a closure, keeping the status menu free of selector plumbing.
final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void
    init(title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("Not used") }
    @objc private func run() { MainActor.assumeIsolated { handler() } }
}
