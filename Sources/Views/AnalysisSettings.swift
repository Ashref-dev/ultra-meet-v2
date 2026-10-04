import AppKit
import SwiftUI

struct AnalysisSettings: View {
    @ObservedObject var state: AppState
    enum KeyStatus: Equatable { case idle, checking, valid(String), invalid(String) }
    @State private var key = ""
    @State private var status = KeyStatus.idle
    @State private var choosingModel = false
    @State private var editing: AnalysisTemplate?
    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    SecureField("API key", text: $key, prompt: Text("sk-or-v1-…"))
                        .onChange(of: key) { _, _ in if status != .checking { status = .idle } }
                        .onSubmit(validate)
                    Button(status == .checking ? "Checking…" : "Validate & Save", action: validate)
                        .buttonStyle(ControlStyle(kind: .primary, compact: true))
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
                }
                keyStatus
            } header: { Text("OpenRouter") } footer: {
                HStack(spacing: 4) {
                    Text("Stored in your macOS Keychain.").font(.caption).foregroundStyle(Theme.secondary)
                    Link("Get a key", destination: URL(string: "https://openrouter.ai/settings/keys")!).font(.caption)
                }
            }
            Section {
                LabeledContent("Model") {
                    Button { choosingModel = true } label: {
                        HStack(spacing: 6) { Text(state.preferences.openRouterModel).font(.system(size: 12, design: .monospaced)); Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)) }
                    }.buttonStyle(ControlStyle(compact: true))
                }
            } footer: { caption("Only the transcript text is sent, and only when you click Analyze with AI. Provider pricing and data policies apply.") }
            Section {
                ForEach(state.preferences.templates) { template in
                    HStack(spacing: 10) {
                        Button { state.preferences.templateID = template.id } label: {
                            Image(systemName: template.id == state.preferences.template.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(template.id == state.preferences.template.id ? Theme.orange : Theme.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("Use \(template.name)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                            Text(template.prompt).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Edit") { editing = template }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    }
                }
                Button { editing = AnalysisTemplate(name: "", prompt: "") } label: {
                    Label("New Template", systemImage: "plus")
                }.buttonStyle(ControlStyle(compact: true))
            } header: { Text("Templates") } footer: {
                caption("A template tells the AI what matters in this kind of meeting. Every analysis includes a title, summary, decisions, and action items for you and your colleagues.")
            }
        }
        .onAppear {
            key = Keychain.read()
            if !key.isEmpty { status = .valid("Saved in Keychain") }
        }
        .sheet(isPresented: $choosingModel) { ModelCatalog(selection: $state.preferences.openRouterModel) }
        .sheet(item: $editing) { template in TemplateEditor(state: state, template: template) }
    }
    @ViewBuilder var keyStatus: some View {
        switch status {
        case .idle: EmptyView()
        case .checking: HStack(spacing: 6) { ProgressView().controlSize(.small); caption("Checking with OpenRouter…") }
        case .valid(let detail):
            HStack(spacing: 6) {
                Label(detail, systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                Spacer()
                Button("Remove Key", role: .destructive) { remove() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
        case .invalid(let message): Label(message, systemImage: "xmark.circle.fill").font(.caption).foregroundStyle(Theme.orange)
        }
    }
    func validate() {
        let candidate = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        status = .checking
        Task {
            do {
                let info = try await OpenRouter.validate(key: candidate)
                try state.saveOpenRouterKey(candidate)
                if state.analysisFailure?.message.contains("API key") == true { state.analysisFailure = nil }
                status = .valid("Valid · \(info.label.map { "\($0) · " } ?? "")\(info.summary)")
            } catch { status = .invalid(error.localizedDescription) }
        }
    }
    func remove() {
        do { try state.saveOpenRouterKey(""); key = ""; status = .idle }
        catch { status = .invalid(error.localizedDescription) }
    }
}

/// Searchable OpenRouter model catalog.
struct ModelCatalog: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var models: [OpenRouterModel] = []
    @State private var query = ""
    @State private var failure: String?
    @State private var loading = true
    var filtered: [OpenRouterModel] {
        let words = query.lowercased().split(separator: " ")
        return models.filter { model in words.allSatisfy { model.name.lowercased().contains($0) || model.id.lowercased().contains($0) } }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a model").font(.system(size: 15, weight: .semibold))
                Spacer()
                MonoLabel(loading ? "Loading" : "\(filtered.count) models")
            }
            .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, 10)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondary)
                TextField("Search, e.g. claude, gemini flash, gpt", text: $query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
            .padding(.horizontal, 18).padding(.bottom, 10)
            Divider()
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failure {
                    VStack(spacing: 10) {
                        Text(failure).font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }.buttonStyle(ControlStyle(compact: true))
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { model in
                        Button { selection = model.id; dismiss() } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: model.id == selection ? "checkmark.circle.fill" : "circle").foregroundStyle(model.id == selection ? Theme.orange : Theme.secondary.opacity(0.5)).padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(model.name).font(.system(size: 13, weight: .medium))
                                    Text(model.id).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(model.priceLabel).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                                    if let context = model.contextLabel { MonoLabel(context) }
                                }
                            }
                            .padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            Divider()
            HStack {
                caption("Prices from OpenRouter, per million tokens.")
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(ControlStyle(compact: true)).keyboardShortcut(.cancelAction)
            }.padding(14)
        }
        .frame(width: 560, height: 520)
        .background(Theme.background)
        .task { await load() }
    }
    func load() async {
        loading = true
        failure = nil
        do { models = try await OpenRouter.catalog() } catch { failure = error.localizedDescription }
        loading = false
    }
}

struct TemplateEditor: View {
    @ObservedObject var state: AppState
    @State var template: AnalysisTemplate
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Analysis template").font(.system(size: 15, weight: .semibold))
            TextField("Name", text: $template.name).textFieldStyle(.roundedBorder).font(.system(size: 13))
            VStack(alignment: .leading, spacing: 6) {
                MonoLabel("Instructions")
                TextEditor(text: $template.prompt)
                    .font(.system(size: 13)).scrollContentBackground(.hidden).padding(8)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
                    .frame(height: 170)
                caption("What should the notes focus on? For example: “Focus on budget, objections and next steps with the client.”")
            }
            HStack {
                Button("Delete", role: .destructive) {
                    state.preferences.templates.removeAll { $0.id == template.id }
                    if state.preferences.templates.isEmpty { state.preferences.templates = AnalysisTemplate.defaults }
                    dismiss()
                }
                .buttonStyle(ControlStyle(kind: .quiet, compact: true))
                .disabled(state.preferences.templates.count <= 1 || !state.preferences.templates.contains { $0.id == template.id })
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(ControlStyle(compact: true)).keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let index = state.preferences.templates.firstIndex(where: { $0.id == template.id }) { state.preferences.templates[index] = template }
                    else { state.preferences.templates.append(template) }
                    dismiss()
                }
                .buttonStyle(ControlStyle(kind: .primary, compact: true)).keyboardShortcut(.defaultAction)
                .disabled(template.name.trimmingCharacters(in: .whitespaces).isEmpty || template.prompt.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 480).background(Theme.background)
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
}
