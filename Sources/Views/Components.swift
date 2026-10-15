import AppKit
import SwiftUI

/// Uppercase monospaced metadata label, the reference design's signature voice.
struct MonoLabel: View {
    let text: String
    var color: Color?
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View {
        let label = Text(text.uppercased()).font(Theme.mono).tracking(0.6).lineLimit(1)
        if let color { label.foregroundStyle(color) } else { label.secondaryText() }
    }
}

extension EnvironmentValues {
    /// True on the menu-bar panel's Liquid Glass; paper cards set it back to false.
    @Entry var onGlass = false
}

/// Secondary text: the warm gray on paper, the system's vibrant secondary on glass so it reads over any background.
private struct SecondaryText: ViewModifier {
    @Environment(\.onGlass) private var onGlass
    func body(content: Content) -> some View {
        content.foregroundStyle(onGlass ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.secondary))
    }
}

enum ControlKind { case primary, secondary, quiet }

/// Shared button chrome: orange glass primary, clear glass secondary, borderless quiet. `square` fits one icon.
struct ControlStyle: ButtonStyle {
    var kind: ControlKind = .secondary
    var expand = false
    var compact = false
    var square = false
    func makeBody(configuration: Configuration) -> some View {
        ControlBody(configuration: configuration, kind: kind, expand: expand, compact: compact, square: square)
    }
    private struct ControlBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: ControlKind
        let expand: Bool
        let compact: Bool
        let square: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var height: CGFloat { compact ? Theme.compactControlHeight : Theme.controlHeight }
        @Environment(\.onGlass) private var onGlass
        var foreground: AnyShapeStyle {
            if kind == .primary { return AnyShapeStyle(.white) }
            if configuration.role == .destructive { return AnyShapeStyle(Theme.destructive) }
            guard kind == .quiet && !hovering else { return AnyShapeStyle(.primary) }
            return onGlass ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.secondary)
        }
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
            configuration.label
                .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, square ? 0 : kind == .quiet ? 8 : compact ? 10 : 12)
                .frame(width: square ? height : nil, height: height)
                .frame(maxWidth: expand ? .infinity : nil)
                .modifier(ControlChrome(kind: kind, shape: shape, pressed: configuration.isPressed, hovering: hovering, enabled: enabled))
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : Theme.feedback, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
                .onHover { hovering = $0 && enabled }
        }
    }
}

private struct ControlChrome: ViewModifier {
    let kind: ControlKind
    let shape: RoundedRectangle
    let pressed: Bool
    let hovering: Bool
    let enabled: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if kind == .quiet {
            content.background(hovering || pressed ? Theme.line : .clear, in: shape)
        } else {
            content.glassSurface(cornerRadius: Theme.controlRadius,
                                 tint: kind == .primary ? (pressed ? Theme.ember : Theme.orange) : nil,
                                 interactive: enabled)
        }
    }
}

/// Square icon button with an accessible name.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ControlStyle(square: true))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// The ellipsis menu for secondary actions.
struct MoreMenu<Items: View>: View {
    let label: String
    @ViewBuilder let items: Items
    var body: some View {
        Menu { items } label: { Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)) }
            .menuStyle(.button).buttonStyle(ControlStyle(compact: true, square: true)).menuIndicator(.hidden).fixedSize()
            .focusEffectDisabled()
            .help(label).accessibilityLabel(label)
    }
}

/// Button label for links that leave the app.
struct LinkLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        HStack(spacing: 4) { Text(title); Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold)) }
    }
}

/// Compact on/off chip, used for language choices.
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    var color: Color = Theme.orange
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        Button { withAnimation(reduceMotion ? nil : Theme.feedback) { isOn.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus").font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isOn ? color : Theme.secondary).contentTransition(.symbolEffect(.replace))
                Text(title).font(.system(size: 12, weight: isOn ? .semibold : .regular)).foregroundStyle(isOn ? Color.primary : Theme.secondary)
            }
            .padding(.horizontal, 10).frame(height: Theme.compactControlHeight)
            .background(isOn ? color.opacity(0.12) : hovering ? Theme.line.opacity(0.5) : .clear, in: shape)
            .overlay(shape.strokeBorder(isOn ? color.opacity(0.45) : Theme.line))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

/// Wraps children onto as many rows as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }
    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty && rows[rows.count - 1].width + spacing + size.width > width {
                let previous = rows[rows.count - 1]
                rows.append(Row(y: previous.y + previous.height + spacing))
            }
            rows[rows.count - 1].width += (rows[rows.count - 1].indices.isEmpty ? 0 : spacing) + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
            rows[rows.count - 1].indices.append(index)
        }
        return rows
    }
}

/// Horizontal shake, used to refuse an action (for example turning off the last audio source).
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}

struct TabItem: Identifiable, Hashable { let id: String; let symbol: String }

/// Content tabs with a sliding orange selection.
struct TabStrip: View {
    let tabs: [TabItem]
    @Binding var selection: String
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { selection = tab.id } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                        Text(tab.id).font(.system(size: 12.5, weight: selection == tab.id ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab.id ? Theme.orange : Theme.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: Theme.controlHeight)
                    .background {
                        if selection == tab.id {
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .fill(Theme.selectionFill).matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .focusEffectDisabled()
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .help("\(tab.id) (⌘\(index + 1))")
                .accessibilityAddTraits(selection == tab.id ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Press feedback without chrome, for custom tiles.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration)
    }
    private struct PressBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            configuration.label
                .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
                .opacity(configuration.isPressed ? 0.82 : 1)
                .animation(reduceMotion ? nil : Theme.feedback, value: configuration.isPressed)
        }
    }
}

/// Hover, press and selected highlight for list rows that behave like buttons.
struct RowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { RowBody(configuration: configuration, selected: selected) }
    private struct RowBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var body: some View {
            configuration.label
                .background(
                    selected ? Theme.selectionFill : hovering || configuration.isPressed ? Theme.line.opacity(0.6) : .clear,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                )
                .contentShape(Rectangle())
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .onHover { hovering = $0 }
                .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
                .animation(reduceMotion ? nil : Theme.feedback, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Theme.selection, value: selected)
        }
    }
}

/// Single-line search with a clear button.
struct SearchField: View {
    let prompt: String
    @Binding var text: String
    /// ⌘F focuses the field when set; the hint shows while it is empty and unfocused.
    var findShortcut = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(focused ? Theme.orange : Theme.secondary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12.5)).focused($focused)
                .onExitCommand { text = ""; focused = false }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondary).accessibilityLabel("Clear search")
                    .transition(.opacity)
            } else if findShortcut && !focused {
                ShortcutHint("⌘F").transition(.opacity)
            }
        }
        .padding(.horizontal, 10).frame(height: Theme.controlHeight)
        .field(focused: focused)
        .animation(reduceMotion ? nil : Theme.feedback, value: focused)
        .animation(reduceMotion ? nil : Theme.feedback, value: text.isEmpty)
        .background {
            if findShortcut {
                Button("Find") { focused = true }.keyboardShortcut("f").opacity(0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

/// Plain keys (no modifiers) pressed in this view's window. Skipped while text is being edited or a sheet is open, so
/// typing is never captured. `handle` returns whether it used the key.
struct KeyMonitor: NSViewRepresentable {
    let handle: (UInt16) -> Bool
    func makeNSView(context: Context) -> Monitor { Monitor() }
    func updateNSView(_ view: Monitor, context: Context) { view.handle = handle }
    final class Monitor: NSView {
        var handle: ((UInt16) -> Bool)?
        private var token: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let token { NSEvent.removeMonitor(token) }
            token = nil
            guard window != nil else { return }
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let used = MainActor.assumeIsolated { () -> Bool in
                    guard let self, let window = self.window, event.window === window, window.isKeyWindow,
                          !(window.firstResponder is NSText),
                          event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
                    return self.handle?(event.keyCode) == true
                }
                return used ? nil : event
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    static let up: UInt16 = 126, down: UInt16 = 125, delete: UInt16 = 51, forwardDelete: UInt16 = 117, space: UInt16 = 49
}

/// A keyboard shortcut shown quietly beside the control it triggers.
struct ShortcutHint: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View {
        Text(keys).font(.system(size: 11, weight: .medium)).secondaryText().opacity(0.8).accessibilityHidden(true)
    }
}

extension View {
    /// Paper surface with a hairline border, for grouped content.
    func card() -> some View {
        environment(\.onGlass, false)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
    }
    func secondaryText() -> some View { modifier(SecondaryText()) }
    /// The menu-bar panel: frosted Liquid Glass tinted toward white in light mode and black in dark mode.
    func panelGlass() -> some View { modifier(PanelGlass()) }
    /// Text input surface; focus is drawn in orange, never the system ring.
    func field(focused: Bool = false) -> some View {
        background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(focused ? Theme.orange.opacity(0.55) : Theme.line, lineWidth: focused ? 1.5 : 1))
    }
    func glassSurface(cornerRadius: CGFloat = Theme.radius, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
    /// A sidebar floating on the window's own color: same fill as the main area, a hairline and a soft shadow.
    func floatingSidebar(_ fill: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        return background(fill, in: shape)
            .overlay(shape.strokeBorder(Theme.line))
            .compositingGroup()
            .shadow(color: Theme.controlShadow, radius: 12, y: 3)
            .padding(.leading, 8).padding(.bottom, 8)
    }
    /// Ultra-thin overlay scrollbars with no track; apply inside the scrolled content (or a list row background).
    func thinScrollbars() -> some View { background(ScrollerHook()) }}

/// Neighboring glass controls share one renderer, so they blend instead of stacking.
struct GlassControls<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?
    let interactive: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency || contrast == .increased {
            content.background(tint ?? Theme.paper, in: shape)
                .overlay(shape.strokeBorder(Theme.secondary.opacity(0.6)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            content.background(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.regularMaterial), in: shape)
                .overlay(shape.strokeBorder(Theme.line))
        }
    }
}

private struct PanelGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
        let panel = content.environment(\.onGlass, true)
        if reduceTransparency || contrast == .increased {
            panel.background(Theme.background, in: shape).overlay(shape.strokeBorder(Theme.secondary.opacity(0.6)))
        } else if #available(macOS 26.0, *) {
            panel.glassEffect(.regular.tint(Theme.glassTint), in: shape)
        } else {
            panel.background { NativeMaterial(material: .popover) }.clipShape(shape).overlay(shape.strokeBorder(Theme.line))
        }
    }
}

/// Finds the enclosing scroll view once it is in a window and gives it the thin scroller.
private struct ScrollerHook: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Hook() }
    func updateNSView(_ view: NSView, context: Context) {}
    final class Hook: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in
                guard let scroll = self?.enclosingScrollView, !(scroll.verticalScroller is ThinScroller) else { return }
                scroll.verticalScroller = ThinScroller()
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A 3 pt rounded knob with no track that widens to 6 pt under the pointer, in the warm secondary color.
final class ThinScroller: NSScroller {
    private var hovering = false {
        didSet { if hovering != oldValue { needsDisplay = true } }
    }
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 12 }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        let width: CGFloat = hovering ? 6 : 3
        let bar = NSRect(x: bounds.maxX - width - 3, y: knob.minY + 3, width: width, height: max(width, knob.height - 6))
        NSColor(Theme.secondary).withAlphaComponent(hovering ? 0.6 : 0.38).setFill()
        NSBezierPath(roundedRect: bar, xRadius: width / 2, yRadius: width / 2).fill()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
}

private struct NativeMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.material = material
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        if view.material != material { view.material = material }
    }
}

// MARK: Surfaces

/// Whether a reused window or the popover is on screen. Hidden surfaces keep their views (so opening is instant)
/// but stop redrawing live audio and progress nobody can see.
@MainActor
final class Visibility: NSObject, ObservableObject {
    @Published var shown = false
    func follow(_ window: NSWindow) {
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }
    @objc private func occlusionChanged(_ notification: Notification) {
        shown = (notification.object as? NSWindow)?.occlusionState.contains(.visible) == true
    }
}

extension EnvironmentValues {
    @Entry var offscreen = false
}

extension LevelMeter {
    /// A meter that never changes, observed instead of the live one while a surface is hidden.
    static let still = LevelMeter()
}

/// Root of every window and the popover: the orange accent everywhere, and live visuals paused while hidden.
struct SurfaceRoot<Content: View>: View {
    @ObservedObject var visibility: Visibility
    let content: Content
    var body: some View {
        content.tint(Theme.orange).environment(\.offscreen, !visibility.shown)
    }
}

// MARK: Content

/// Meeting name that reads as a heading and edits in place. Hover reveals a field and a pencil.
struct EditableTitle: View {
    let title: String
    var size: CGFloat = 26
    let rename: (String) -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Wraps instead of clipping long AI titles; Return still finishes the rename.
            TextField("Meeting name", text: Binding(get: { title }, set: rename), axis: .vertical)
                .textFieldStyle(.plain).lineLimit(1...3)
                .font(.system(size: size, weight: .semibold)).tracking(size > 20 ? -0.5 : -0.3)
                .focused($focused)
                .focusEffectDisabled()
                .onSubmit { focused = false }
            Image(systemName: "pencil").font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(focused ? Theme.orange : Theme.secondary)
                .opacity(hovering || focused ? 1 : 0)
                .offset(x: hovering || focused ? 0 : -4)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(shape.fill(focused ? Theme.paper : hovering ? Theme.line.opacity(0.6) : .clear))
        .overlay(shape.strokeBorder(focused ? Theme.orange.opacity(0.55) : .clear, lineWidth: 1.5))
        .padding(.horizontal, -8)
        .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
        .animation(reduceMotion ? nil : Theme.feedback, value: focused)
        .onHover { hovering = $0 }
        .help("Click to rename")
        .accessibilityLabel("Meeting name")
    }
}

/// Speaker avatar: initial on the speaker's color, with an optional live-level halo.
struct SpeakerAvatar: View {
    let source: String
    var size: CGFloat = 24
    var level: Float = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let color = Theme.speakerColor(source)
        Text(source == "microphone" ? "Y" : source == "system" ? "C" : "S")
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .background(Circle().fill(color.opacity(0.25)).scaleEffect(1 + CGFloat(min(level, 1)) * 0.55))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
            .accessibilityHidden(true)
    }
}

/// Dot-matrix progress. `nil`, or no progress yet, shows a travelling pulse so a starting task never looks stalled.
struct DotProgress: View {
    var value: Double?
    var dots = 32
    var color: Color = Theme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreen) private var offscreen
    var body: some View {
        let value = self.value.flatMap { $0 > 0 ? $0 : nil }
        TimelineView(.animation(minimumInterval: 0.08, paused: value != nil || reduceMotion || offscreen)) { timeline in
            Canvas { context, size in
                let pitch = size.width / CGFloat(dots)
                let diameter = min(pitch * 0.62, size.height)
                let filled = Int((value ?? 0) * Double(dots))
                let head = reduceMotion ? dots / 2 : Int(timeline.date.timeIntervalSinceReferenceDate * 14) % (dots + 6) - 3
                for index in 0..<dots {
                    let rect = CGRect(x: CGFloat(index) * pitch + (pitch - diameter) / 2, y: (size.height - diameter) / 2, width: diameter, height: diameter)
                    let lit = value == nil ? max(0.16, 1 - Double(abs(index - head)) * 0.28) : index < filled ? 1 : 0
                    context.fill(Path(ellipseIn: rect), with: .color(lit > 0.16 ? color.opacity(lit) : Theme.secondary.opacity(0.18)))
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(value.map { "\(Int($0 * 100)) percent" } ?? "In progress")
    }
}

/// Dot-matrix waveform. Recording: real level history scrolling right-to-left, deep green to green where you speak
/// and ember to orange where colleagues speak, dark at the center line and lighter toward the edges. Idle: a quiet
/// ember-to-orange shape on the lattice. Only a visible, live waveform follows the meter.
struct DotWaveform: View {
    let meter: LevelMeter
    var live = false
    var paused = false
    var spacing: CGFloat = 6
    @Environment(\.offscreen) private var offscreen
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DotMatrix(meter: live && !offscreen ? meter : .still, live: live, spacing: spacing)
            .opacity(paused ? 0.4 : 1)
            .animation(reduceMotion ? nil : Theme.feedback, value: paused)
            .accessibilityElement()
            .accessibilityLabel(live ? (paused ? "Recording paused" : "Live audio levels") : "Waveform")
    }
}

private struct DotMatrix: View {
    @ObservedObject var meter: LevelMeter
    let live: Bool
    let spacing: CGFloat
    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width / spacing)
            let rows = max(1, Int(size.height / spacing))
            let middle = Double(rows - 1) / 2
            let history = meter.history
            let xInset = (size.width - CGFloat(columns) * spacing) / 2
            let yInset = (size.height - CGFloat(rows) * spacing) / 2
            for column in 0..<columns {
                let index = history.count - columns + column
                let sample = live && index >= 0 ? history[index] : LevelMeter.Sample(you: 0, colleagues: 0)
                let shades = Theme.shades(sample.colleagues > sample.you ? "system" : "microphone")
                let level = Double(max(sample.you, sample.colleagues))
                let reach = live ? pow(level, 1.4) * (middle + 0.6) : idleReach(column, columns: columns, middle: middle)
                for row in 0..<rows {
                    let distance = abs(Double(row) - middle)
                    let active = distance <= reach && (!live || level > 0.12)
                    let edge = min(1, distance / max(1, reach + 0.5))
                    let fill: Color = !active ? Theme.secondary.opacity(0.11)
                        : live ? shades.deep.mix(with: shades.light, by: edge)
                        : Theme.colleaguesDeep.mix(with: Theme.orange, by: edge).opacity(0.5)
                    let rect = CGRect(x: xInset + CGFloat(column) * spacing + spacing / 2 - 1.6, y: yInset + CGFloat(row) * spacing + spacing / 2 - 1.6, width: 3.2, height: 3.2)
                    context.fill(Path(ellipseIn: rect), with: .color(fill))
                }
            }
        }
    }
    private func idleReach(_ column: Int, columns: Int, middle: Double) -> Double {
        let edge = min(column, columns - 1 - column)
        guard edge > 3 else { return -1 }
        let phase = Double(column) * 0.45
        return abs(sin(phase) * 0.6 + sin(phase * 1.7) * 0.4) * middle * 0.38
    }
}

/// The small switch used by source pills and settings rows.
struct SwitchKnob: View {
    let isOn: Bool
    var color: Color = Theme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? color : Theme.secondary.opacity(0.25))
            Circle().fill(.white).frame(width: 12, height: 12).padding(2).shadow(color: Theme.controlShadow, radius: 1, y: 0.5)
        }
        .frame(width: 28, height: 16)
        .animation(reduceMotion ? nil : Theme.selection, value: isOn)
        .accessibilityHidden(true)
    }
}

/// Segmented choice with a sliding paper thumb, inset concentrically in the track.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var inset: CGFloat { 2 }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { selection = value } } label: {
                    Text(title).font(.system(size: 11.5, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.primary : Theme.secondary)
                        .padding(.horizontal, 10).frame(height: Theme.compactControlHeight - Self.inset * 2)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: Theme.controlRadius - Self.inset, style: .continuous).fill(Theme.paper)
                                    .shadow(color: Theme.controlShadow, radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .accessibilityAddTraits(selection == value ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(Self.inset)
        .background(Theme.line, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// A keyboard shortcut drawn as key caps.
struct KeyCaps: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key).font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 4)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.line))
                    .shadow(color: Theme.controlShadow, radius: 0, y: 1)
            }
        }
        .accessibilityLabel(keys.joined())
    }
}
