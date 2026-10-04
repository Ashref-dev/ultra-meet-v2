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

/// Shared button chrome: orange primary, paper secondary, borderless quiet. Hover, press and disabled states included.
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
        var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous) }
        var body: some View {
            configuration.label
                .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold, design: .monospaced))
                .tracking(0.5)
                .textCase(.uppercase)
                .lineLimit(1)
                .foregroundStyle(kind == .primary ? Color.white : kind == .quiet ? (hovering ? Color.primary : Theme.secondary) : Color.primary)
                .padding(.horizontal, kind == .quiet ? 7 : compact ? 10 : 14)
                .frame(height: compact ? 26 : 34)
                .frame(maxWidth: expand ? .infinity : nil)
                .background(background, in: shape)
                .overlay { if kind == .secondary { shape.strokeBorder(hovering ? Theme.secondary.opacity(0.35) : Theme.line) } }
                .shadow(color: kind == .primary && hovering ? Theme.orange.opacity(0.35) : .clear, radius: 8, y: 2)
                .contentShape(shape)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .opacity(enabled ? 1 : 0.45)
                .animation(reduceMotion ? nil : Theme.feedback, value: configuration.isPressed)
                .animation(reduceMotion ? nil : Theme.feedback, value: hovering)
                .onHover { hovering = $0 && enabled }
        }
        var background: Color {
            switch kind {
            case .primary: return configuration.isPressed ? Theme.ember : Theme.orange
            case .secondary: return configuration.isPressed ? Theme.background : Theme.paper
            case .quiet: return hovering || configuration.isPressed ? Theme.line : .clear
            }
        }
    }
}

/// Square icon button with the same chrome as `ControlStyle.secondary`.
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
    var body: some View {
        Button { withAnimation(Theme.feedback) { isOn.toggle() } } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark" : "plus").font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(isOn ? color : Theme.secondary).contentTransition(.symbolEffect(.replace))
                Text(title).font(.system(size: 12, weight: isOn ? .semibold : .regular)).foregroundStyle(isOn ? Color.primary : Theme.secondary)
            }
            .padding(.horizontal, 10).frame(height: 26)
            .background(isOn ? color.opacity(0.10) : hovering ? Theme.line.opacity(0.5) : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(isOn ? color.opacity(0.45) : Theme.line))
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

/// Mono tab strip with a sliding orange indicator, as in the reference recorder.
struct TabStrip: View {
    let tabs: [TabItem]
    @Binding var selection: String
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { selection = tab.id } } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.symbol).font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(selection == tab.id ? Theme.orange : Theme.secondary)
                            Text(tab.id.uppercased()).font(Theme.mono).tracking(0.6)
                                .foregroundStyle(selection == tab.id ? Color.primary : Theme.secondary)
                        }
                        ZStack {
                            Color.clear.frame(height: 2)
                            if selection == tab.id { Capsule().fill(Theme.orange).frame(height: 2).matchedGeometryEffect(id: "tab", in: indicator) }
                        }
                    }
                    .padding(.top, 9)
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
    /// White paper surface with hairline border and soft lift.
    func card() -> some View {
        background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
            .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
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

/// Dot-matrix progress. `value == nil` shows a travelling pulse.
struct DotProgress: View {
    var value: Double?
    var dots = 32
    var color: Color = Theme.orange
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: value != nil)) { timeline in
            Canvas { context, size in
                let pitch = size.width / CGFloat(dots)
                let diameter = min(pitch * 0.62, size.height)
                let filled = Int((value ?? 0) * Double(dots))
                let head = Int(timeline.date.timeIntervalSinceReferenceDate * 14) % (dots + 6) - 3
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

/// Dot-matrix waveform. Recording: real level history scrolling right-to-left, green where you speak and
/// orange where colleagues speak. Idle: a quiet static lattice.
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
                let color = sample.colleagues > sample.you ? Theme.colleagues : Theme.you
                let level = Double(max(sample.you, sample.colleagues))
                let reach = live ? pow(level, 1.4) * (middle + 0.6) : idleReach(column, columns: columns, middle: middle)
                for row in 0..<rows {
                    let distance = abs(Double(row) - middle)
                    let active = distance <= reach && (!live || level > 0.12)
                    let fill: Color = !active ? Theme.secondary.opacity(0.11) : live ? color.opacity(1 - distance / (middle + 1.5) * 0.6) : Theme.secondary.opacity(0.32)
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
