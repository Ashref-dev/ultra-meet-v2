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

    init(state: AppState) {
        self.state = state
        super.init()
        item.autosaveName = "UltraTranscribe"
        item.behavior = []
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
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
        menu.addItem(.separator())
        menu.addItem(entry("Meeting Library…", symbol: "list.bullet.rectangle") { [state] in state.showMeeting(nil) })
        menu.addItem(entry("Settings…", symbol: "gearshape") { [state] in state.showSettings(.general) })
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

    private func refresh() {
        guard let button = item.button else { return }
        let recording = state.activeID != nil
        let paused = recording && state.recorder.paused
        let title = recording ? Meeting.timestamp(state.elapsed) : state.processingID != nil ? "\(Int(state.engine.fraction * 100))%" : ""
        let levels = recording ? columnLevels(paused: paused) : nil
        let key = "\(title)|\(levels.map { $0.map { Int($0 * 5) } } ?? [])"
        guard key != appearance else { return }
        appearance = key
        button.image = Self.icon(levels: levels)
        button.attributedTitle = title.isEmpty ? NSAttributedString() : NSAttributedString(string: " " + title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: paused ? NSColor.secondaryLabelColor : NSColor.labelColor
        ])
        button.setAccessibilityValue(recording ? "\(paused ? "Paused" : "Recording") \(title)" : title.isEmpty ? "Ready" : "Transcribing \(title)")
    }

    /// The last few level samples, one per logo column, so the icon itself moves with the conversation.
    private func columnLevels(paused: Bool) -> [Double] {
        let count = LogoGlyph.heights.count
        guard !paused else { return Array(repeating: 0, count: count) }
        let samples = state.recorder.levels.history.suffix(count).map { Double(max($0.you, $0.colleagues)) }
        return samples.enumerated().map { index, level in
            let shape = Double(LogoGlyph.heights[index]) / Double(LogoGlyph.rows)
            return max(0.2, min(1, pow(level, 1.3) * 1.2 * (0.55 + shape * 0.45)))
        }
    }

    /// The dot-matrix logo as a template image; recording swaps the fixed shape for live levels.
    private static func icon(levels: [Double]?) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            LogoGlyph.draw(in: rect.insetBy(dx: 1, dy: 1.5), levels: levels) { NSBezierPath(ovalIn: $0).fill() }
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
