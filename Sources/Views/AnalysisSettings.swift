import AppKit
import SwiftUI

struct AnalysisSettings: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var choosingModel = false
    @State private var editing: AnalysisTemplate?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "OpenRouter key", footer: "Stored in your macOS Keychain. Only text is sent (the transcript and your notes), and only when you click Analyze with AI or turn on analysis after transcription.") {
                OpenRouterKeyField(state: state)
            }
            SettingsSection(title: "Automatic notes") {
                SettingsToggle(title: "Analyze after transcription", detail: "Writes AI notes as soon as a meeting is transcribed, with the selected template. Sends the transcript text to OpenRouter each time.", isOn: $state.preferences.analyzeAfterTranscription)
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
                .padding(.horizontal, 4).frame(minHeight: 40)
            }
        }
        .sheet(isPresented: $choosingModel) { ModelCatalog(selection: $state.preferences.openRouterModel) }
        .sheet(item: $editing) { template in TemplateEditor(state: state, template: template) }
    }
    func templateRow(_ template: AnalysisTemplate) -> some View {
        let selected = template.id == state.preferences.template.id
        return HStack(spacing: 12) {
            Button { withAnimation(reduceMotion ? nil : Theme.feedback) { state.preferences.templateID = template.id } } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(selected ? Theme.orange : Theme.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 16, height: 16)
                        if selected { Circle().fill(Theme.orange).frame(width: 8, height: 8).transition(reduceMotion ? .identity : .scale) }
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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 40)
    }
}

/// OpenRouter key entry with validation, shared by Settings and first-run setup. Reads the Keychain only when shown.
struct OpenRouterKeyField: View {
    @ObservedObject var state: AppState
    enum KeyStatus: Equatable { case idle, checking, valid(String), invalid(String) }
    @State private var key = ""
    /// The key in the Keychain, so loading it doesn't count as an edit that needs validating again.
    @State private var saved = ""
    @State private var status = KeyStatus.idle
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "key").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                SecureField("", text: $key, prompt: Text("sk-or-v1-…"))
                    .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced)).focusEffectDisabled()
                    .onChange(of: key) { _, value in if value != saved && status != .checking { status = .idle } }
                    .onSubmit(validate)
                Button(status == .checking ? "Checking" : "Validate & Save", action: validate)
                    .buttonStyle(ControlStyle(kind: .primary, compact: true))
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || status == .checking)
            }
            .padding(.horizontal, 12).frame(minHeight: 44)
            RowDivider()
            HStack(spacing: 8) {
                keyStatus
                Spacer()
                Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) { LinkLabel("Get a key") }
                .buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
            .padding(.leading, 12).padding(.trailing, 8).frame(minHeight: 40)
        }
        .onAppear {
            saved = state.readKey()
            key = saved
            if !key.isEmpty { status = .valid("Saved in Keychain") }
        }
    }
    @ViewBuilder var keyStatus: some View {
        switch status {
        case .idle: Text("Not validated yet").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        case .checking: HStack(spacing: 6) { DotProgress(value: nil, dots: 10).frame(width: 50, height: 5); Text("Checking with OpenRouter…").font(.system(size: 11.5)).foregroundStyle(Theme.secondary) }
        case .valid(let detail):
            HStack(spacing: 8) {
                Label(detail, systemImage: "checkmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(Theme.youText).lineLimit(1)
                Button("Remove", role: .destructive) { remove() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
            }
        case .invalid(let message): Label(message, systemImage: "xmark.circle.fill").font(.system(size: 11.5)).foregroundStyle(Theme.destructive).lineLimit(2)
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
                saved = candidate
                if state.analysisFailure?.message.contains("API key") == true { state.analysisFailure = nil }
                status = .valid("Valid · \(info.label.map { "\($0) · " } ?? "")\(info.summary)")
            } catch { status = .invalid(error.localizedDescription) }
        }
    }
    func remove() {
        do { try state.saveOpenRouterKey(""); saved = ""; key = ""; status = .idle }
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
        let results = filtered
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.orange)
                Text("Choose a model").font(.system(size: 18, weight: .semibold))
                Spacer()
                MonoLabel(loading ? "Loading" : "\(results.count) models")
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
            SearchField(prompt: "Search, e.g. claude, gemini flash, gpt", text: $query)
                .padding(.horizontal, 20).padding(.bottom, 12)
            Divider()
            Group {
                if loading {
                    VStack(spacing: 12) {
                        DotProgress(value: nil, dots: 24).frame(width: 144, height: 6)
                        Text("Loading models…").font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failure {
                    VStack(spacing: 10) {
                        Text(failure).font(.system(size: 12)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { Task { await load() } }.buttonStyle(ControlStyle(compact: true))
                    }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results) { model in
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
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear.thinScrollbars())
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .background(Theme.paper)
                }
            }
            Divider()
            HStack(spacing: 12) {
                caption("Prices from OpenRouter, per million tokens.")
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(ControlStyle(compact: true)).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 560, height: 520)
        .background(Theme.background.ignoresSafeArea())
        .tint(Theme.orange)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State var template: AnalysisTemplate
    @Environment(\.dismiss) private var dismiss
    private enum Field { case name, prompt }
    @FocusState private var focus: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "text.badge.star").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.orange)
                Text("Analysis template").font(.system(size: 18, weight: .semibold))
            }
            TextField("Name", text: $template.name)
                .textFieldStyle(.plain).font(.system(size: 13)).focusEffectDisabled()
                .focused($focus, equals: .name)
                .padding(.horizontal, 10).frame(height: Theme.controlHeight)
                .field(focused: focus == .name)
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Instructions")
                TextEditor(text: $template.prompt)
                    .font(.system(size: 13)).scrollContentBackground(.hidden).focusEffectDisabled()
                    .focused($focus, equals: .prompt)
                    .padding(8)
                    .field(focused: focus == .prompt)
                    .frame(height: 168)
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
                GlassControls {
                    HStack(spacing: 8) {
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
            }
        }
        .padding(20).frame(width: 480).background(Theme.background.ignoresSafeArea())
        .tint(Theme.orange)
        .animation(reduceMotion ? nil : Theme.feedback, value: focus)
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
}
