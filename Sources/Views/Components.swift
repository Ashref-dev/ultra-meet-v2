import AppKit
import SwiftUI

/// Uppercase monospaced metadata label, the reference design's signature voice.
struct MonoLabel: View {
    let text: String
    var color: Color = Theme.secondary
    init(_ text: String, color: Color = Theme.secondary) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased()).font(Theme.mono).tracking(0.6).foregroundStyle(color).lineLimit(1)
    }
}

enum ControlKind { case primary, secondary, quiet }

/// Shared action chrome. Glass belongs on controls, not on the text people read.
struct ControlStyle: ButtonStyle {
    var kind: ControlKind = .secondary
    var expand = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        ControlBody(configuration: configuration, kind: kind, expand: expand, compact: compact)
    }
    private struct ControlBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: ControlKind
        let expand: Bool
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false
        var shape: RoundedRectangle { RoundedRectangle(cornerRadius: (compact ? Theme.compactControlHeight : Theme.controlHeight) / 2, style: .continuous) }
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 11.5 : 12.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(kind == .primary ? Color.white : kind == .quiet ? (hovering ? Color.primary : Theme.secondary) : Color.primary)
                .padding(.horizontal, kind == .quiet ? 7 : compact ? 10 : 14)
                .frame(height: compact ? Theme.compactControlHeight : Theme.controlHeight)
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
            content.background(hovering || pressed ? Theme.line.opacity(0.5) : .clear, in: shape)
        } else {
            content.glassSurface(cornerRadius: shape.cornerSize.width,
                                 tint: kind == .primary ? (pressed ? Theme.ember : Theme.orange) : nil,
                                 interactive: enabled)
        }
    }
}

/// Icon-only action with the shared glass chrome and an accessible name.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).frame(width: 14).contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(ControlStyle(kind: .secondary))
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Compact on/off pill, used for language choices.
struct ToggleChip: View {
    let title: String
    @Binding var isOn: Bool
    var color: Color = Theme.orange
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button { withAnimation(reduceMotion ? nil : Theme.feedback) { isOn.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus").font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isOn ? color : Theme.secondary).contentTransition(.symbolEffect(.replace))
                Text(title).font(.system(size: 12, weight: isOn ? .semibold : .regular)).foregroundStyle(isOn ? Color.primary : Theme.secondary)
            }
            .padding(.horizontal, 11).frame(height: Theme.compactControlHeight)
            .background(isOn ? color.opacity(0.12) : hovering ? Theme.line.opacity(0.35) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? color.opacity(0.45) : Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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

/// Content tabs stay on the reading surface; the selected capsule marks the current pane.
struct TabStrip: View {
    let tabs: [TabItem]
    @Binding var selection: String
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { selection = tab.id } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 11, weight: .semibold))
                        Text(tab.id).font(.system(size: 12.5, weight: selection == tab.id ? .semibold : .medium))
                    }
                    .foregroundStyle(selection == tab.id ? Theme.orange : Theme.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: Theme.controlHeight)
                    .background {
                        if selection == tab.id {
                            Capsule().fill(Theme.selectionFill).matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab.id ? [.isSelected, .isButton] : .isButton)
            }
            Spacer(minLength: 0)
        }
    }
}

extension View {
    /// Opaque grouped content keeps transcripts and settings readable beside translucent chrome.
    func card() -> some View {
        background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line.opacity(0.5)))
    }
    func glassSurface(cornerRadius: CGFloat = Theme.radius, tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }
    func sidebarSurface() -> some View { background { ChromeSurface(material: .sidebar).ignoresSafeArea() } }
    func popoverSurface() -> some View { background { ChromeSurface(material: .popover).ignoresSafeArea() } }
}

/// A single effect container lets related controls share the system's glass renderer.
struct GlassControls<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 4) { content }
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
    var shape: RoundedRectangle { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous) }

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(tint ?? Theme.paper, in: shape)
                .overlay(shape.strokeBorder(Theme.secondary.opacity(0.6)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
        } else if let tint {
            content.background(tint, in: shape)
                .overlay(shape.strokeBorder(Theme.line))
        } else {
            content.background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Theme.line))
        }
    }
}

private struct ChromeSurface: View {
    let material: NSVisualEffectView.Material
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        if reduceTransparency || contrast == .increased {
            Theme.background
        } else {
            NativeMaterial(material: material)
        }
    }
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
        view.material = material
    }
}

/// Meeting name that reads as a heading and edits in place. Hover reveals a field and a pencil.
struct EditableTitle: View {
    let title: String
    var size: CGFloat = 24
    let rename: (String) -> Void
    @State private var hovering = false
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            TextField("Meeting name", text: Binding(get: { title }, set: rename))
                .textFieldStyle(.plain)
                .font(.system(size: size, weight: .semibold)).tracking(size > 20 ? -0.5 : -0.3)
                .focused($focused)
                .onSubmit { focused = false }
            Image(systemName: "pencil").font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(focused ? Theme.orange : Theme.secondary)
                .opacity(hovering || focused ? 1 : 0)
                .offset(x: hovering || focused ? 0 : -4)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).fill(focused ? Theme.paper : hovering ? Theme.line.opacity(0.55) : .clear))
        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(focused ? Theme.orange.opacity(0.55) : .clear, lineWidth: 1.5))
        .padding(.horizontal, -7)
        .animation(Theme.feedback, value: hovering)
        .animation(Theme.feedback, value: focused)
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
    var body: some View {
        let color = Theme.speakerColor(source)
        Text(source == "microphone" ? "Y" : source == "system" ? "C" : "S")
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: Circle())
            .background(Circle().fill(color.opacity(0.25)).scaleEffect(1 + CGFloat(min(level, 1)) * 0.55))
            .animation(.easeOut(duration: 0.12), value: level)
            .accessibilityHidden(true)
    }
}

/// Dot-matrix progress. `nil`, or no progress yet, shows a travelling pulse so a starting task never looks stalled.
struct DotProgress: View {
    var value: Double?
    var dots = 32
    var color: Color = Theme.orange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let value = self.value.flatMap { $0 > 0 ? $0 : nil }
        TimelineView(.animation(minimumInterval: 0.08, paused: value != nil || reduceMotion)) { timeline in
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
/// ember-to-orange shape on the lattice.
struct DotWaveform: View {
    @ObservedObject var meter: LevelMeter
    var live = false
    var paused = false
    var spacing: CGFloat = 6
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
        .opacity(paused ? 0.4 : 1)
        .animation(Theme.feedback, value: paused)
        .accessibilityElement()
        .accessibilityLabel(live ? (paused ? "Recording paused" : "Live audio levels") : "Waveform")
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
            Circle().fill(.white).frame(width: 14, height: 14).padding(3).shadow(color: Theme.controlShadow, radius: 1)
        }
        .frame(width: 32, height: 20)
        .animation(reduceMotion ? nil : Theme.selection, value: isOn)
        .accessibilityHidden(true)
    }
}

/// Compact grouped choices with a sliding, opaque selection thumb.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { selection = value } } label: {
                    Text(title).font(.system(size: 11.5, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.primary : Theme.secondary)
                        .padding(.horizontal, 11).frame(height: Theme.compactControlHeight)
                        .background {
                            if selection == value {
                                Capsule().fill(Theme.paper)
                                    .shadow(color: Theme.controlShadow, radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(Theme.line.opacity(0.35), in: Capsule())
    }
}

/// A keyboard shortcut drawn as key caps.
struct KeyCaps: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key).font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .frame(minWidth: 18, minHeight: 18).padding(.horizontal, 3)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(Theme.line))
                    .shadow(color: .black.opacity(0.06), radius: 0, y: 1)
            }
        }
        .accessibilityLabel(keys.joined())
    }
}
