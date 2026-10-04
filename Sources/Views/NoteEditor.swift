import AppKit
import SwiftUI

/// Multiline note field: Return adds lines, content scrolls inside, and text fades out at the top and
/// bottom edges as it scrolls, like the reference transcript card.
struct NoteEditor: View {
    @Binding var text: String
    var placeholder = "Jot a note…"
    var fontSize: CGFloat = 12.5
    var inset = CGSize(width: 8, height: 12)
    var fade: CGFloat = 14
    var framed = true
    @State private var focused = false
    @State private var hovering = false
    var body: some View {
        NoteTextView(text: $text, focused: $focused, fontSize: fontSize, inset: inset)
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
                }
            )
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(.system(size: fontSize)).foregroundStyle(Theme.secondary.opacity(0.7))
                        .padding(.leading, inset.width + 5).padding(.top, inset.height).allowsHitTesting(false)
                }
            }
            .background(framed ? Theme.background : .clear, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                if framed {
                    RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                        .strokeBorder(focused ? Theme.orange.opacity(0.55) : hovering ? Theme.line : .clear, lineWidth: focused ? 1.5 : 1)
                }
            }
            .animation(Theme.feedback, value: focused)
            .animation(Theme.feedback, value: hovering)
            .onHover { hovering = $0 }
            .accessibilityLabel(placeholder)
    }
}

private struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    let fontSize: CGFloat
    let inset: CGSize
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .allowed
        let view = FocusTextView()
        view.onFocus = { focused in DispatchQueue.main.async { context.coordinator.parent.focused = focused } }
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        scroll.documentView = view
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.font = .systemFont(ofSize: fontSize)
        view.textColor = .labelColor
        view.insertionPointColor = NSColor(Theme.orange)
        view.textContainerInset = inset
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        view.defaultParagraphStyle = paragraph
        view.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        view.string = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        view.string = text
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteTextView
        init(_ parent: NoteTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

private final class FocusTextView: NSTextView {
    var onFocus: (Bool) -> Void = { _ in }
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus(true) }
        return accepted
    }
    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocus(false) }
        return accepted
    }
}
