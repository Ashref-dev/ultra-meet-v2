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
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "OpenRouter key", footer: "Stored in your macOS Keychain. Only the transcript text is sent, and only when you click Analyze with AI.") {
                HStack(spacing: 8) {
                    Image(systemName: "key").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    SecureField("", text: $key, prompt: Text("sk-or-v1-…"))
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                        .onChange(of: key) { _, _ in if status != .checking { status = .idle } }
                        .onSubmit(validate)
                    Button(status == .checking ? "Checking" : "Validate & Save", action: validate)
                        .buttonStyle(ControlStyle(kind: .primary, compact: true))
                        .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
                }
                .padding(.horizontal, 14).frame(height: 46)
                RowDivider()
                HStack(spacing: 8) {
                    keyStatus
                    Spacer()
                    Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) {
                        HStack(spacing: 4) { Text("Get a key"); Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold)) }
                    }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true))
                }
                .padding(.horizontal, 14).frame(height: 40)
            }
            SettingsSection(title: "Model", footer: "Prices and data policies are the provider’s. Larger models write better notes; fast ones answer in seconds.") {
                SettingsRow(title: state.preferences.openRouterModel.components(separatedBy: "/").last ?? state.preferences.openRouterModel, detail: state.preferences.openRouterModel) {
                    Button("Change…") { choosingModel = true }.buttonStyle(ControlStyle(compact: true))
                }
            }
            SettingsSection(title: "Templates", footer: "A template is the system prompt for a kind of meeting. Every analysis also gets a title, summary, decisions and action items for you and your colleagues.") {
                ForEach(Array(state.preferences.templates.enumerated()), id: \.element.id) { index, template in
                    if index > 0 { RowDivider() }
                    templateRow(template)
                }
                RowDivider()
                HStack {
                    Button { editing = AnalysisTemplate(name: "", prompt: "") } label: { Label("New template", systemImage: "plus") }
                        .buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 40)
            }
        }
        .onAppear {
            key = Keychain.read()
            if !key.isEmpty { status = .valid("Saved in Keychain") }
        }
        .sheet(isPresented: $choosingModel) { ModelCatalog(selection: $state.preferences.openRouterModel) }
        .sheet(item: $editing) { template in TemplateEditor(state: state, template: template) }
    }
    func templateRow(_ template: AnalysisTemplate) -> some View {
        let selected = template.id == state.preferences.template.id
        return HStack(spacing: 12) {
            Button { withAnimation(Theme.feedback) { state.preferences.templateID = template.id } } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(selected ? Theme.orange : Theme.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 16, height: 16)
                        if selected { Circle().fill(Theme.orange).frame(width: 8, height: 8).transition(.scale) }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        Text(template.prompt).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Use \(template.name)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button("Edit") { editing = template }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }
    @ViewBuilder var keyStatus: some View {
        switch status {
        case .idle: Text("Not validated yet").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        case .checking: HStack(spacing: 6) { DotProgress(value: nil, dots: 10).frame(width: 50, height: 5); Text("Checking with OpenRouter…").font(.system(size: 11.5)).foregroundStyle(Theme.secondary) }
        case .valid(let detail):
            HStack(spacing: 8) {
                Label(detail, systemImage: "checkmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(Theme.you).lineLimit(1)
                Button("Remove", role: .destructive) { remove() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
        case .invalid(let message): Label(message, systemImage: "xmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(Theme.orange).lineLimit(2)
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
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.line))
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
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.line))
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
