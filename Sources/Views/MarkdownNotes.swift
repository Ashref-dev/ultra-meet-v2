import SwiftUI

/// Renders the small Markdown subset the analysis prompt asks for: headings, bullets, task checkboxes and inline emphasis.
struct MarkdownNotes: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, raw in
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("### ") {
                    MonoLabel(String(line.dropFirst(4)), color: .primary).padding(.top, 8)
                } else if line.hasPrefix("#") {
                    Text(line.drop(while: { $0 == "#" || $0 == " " }))
                        .font(.system(size: line.hasPrefix("# ") ? 21 : 16, weight: .semibold)).tracking(-0.2)
                        .padding(.top, 16).padding(.bottom, 2)
                } else if let task = taskText(line) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Image(systemName: task.done ? "checkmark.square.fill" : "square").font(.system(size: 12)).foregroundStyle(Theme.orange)
                        inline(task.text)
                    }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Theme.orange).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                        inline(String(line.dropFirst(2)))
                    }
                    .padding(.leading, raw.hasPrefix("  ") ? 16 : 0)
                } else if line == "None." || line == "None" {
                    Text("None").font(.system(size: 14)).foregroundStyle(Theme.secondary)
                } else if !line.isEmpty {
                    inline(line)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    func taskText(_ line: String) -> (done: Bool, text: String)? {
        for (prefix, done) in [("- [ ] ", false), ("- [x] ", true), ("- [X] ", true), ("* [ ] ", false)] where line.hasPrefix(prefix) {
            return (done, String(line.dropFirst(prefix.count)))
        }
        return nil
    }
    func inline(_ line: String) -> some View {
        Text((try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line))
            .font(.system(size: 14)).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
    }
}
