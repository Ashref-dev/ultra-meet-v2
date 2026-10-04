import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding(get: { state.settingsPane }, set: { if let pane = $0 { state.settingsPane = pane } })) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch state.settingsPane {
                case .general: GeneralSettings(state: state)
                case .recording: RecordingSettings(state: state)
                case .transcription: TranscriptionSettings(state: state)
                case .analysis: AnalysisSettings(state: state)
                case .storage: StorageSettings(state: state)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(state.settingsPane.title)
        }
        .tint(Theme.orange)
        .toggleStyle(.switch)
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: state.preferences) { _, _ in state.savePreferences() }
    }
}

private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
}

struct GeneralSettings: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $state.preferences.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
                Toggle("Open at login", isOn: Binding(get: { state.preferences.launchAtLogin }, set: { state.setLogin($0) }))
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            } footer: { caption("Ultra Transcribe lives in the menu bar. Left-click the icon for the recorder, right-click for quick actions.") }
            Section("Keyboard") {
                shortcut("Start recording", "⌘N")
                shortcut("Pause or resume", "⌘⇧P")
                shortcut("Stop and transcribe", "⌘⇧S")
                shortcut("Meeting library", "⌘L")
                shortcut("Import audio", "⌘O")
                shortcut("Settings", "⌘,")
            }
            Section { caption("Ultra Transcribe 2.0 · Made by ashref.tn") }
        }
        .onAppear { state.refreshLoginStatus() }
    }
    func shortcut(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) { Text(keys).font(Theme.mono).foregroundStyle(Theme.secondary) }
    }
}

struct RecordingSettings: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section {
                Toggle(isOn: source(microphone: true)) { Label { Text("You") ; caption("Your microphone") } icon: { dot(Theme.you) } }
                Toggle(isOn: source(microphone: false)) { Label { Text("Colleagues"); caption("Audio from your Mac: calls, browser, apps") } icon: { dot(Theme.colleagues) } }
            } header: { Text("Record by default") } footer: {
                caption("Separate tracks let transcripts and AI notes tell who said what. Use headphones so your microphone doesn’t pick up your colleagues; duplicates are removed when it does.")
            }
            Section {
                LabeledContent("Microphone", value: AVCaptureDevice.default(for: .audio)?.localizedName ?? "No input device")
                LabeledContent("Mic mode") {
                    HStack(spacing: 8) {
                        Text(micMode).foregroundStyle(Theme.secondary)
                        Button("Change…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }.buttonStyle(ControlStyle(compact: true))
                    }
                }
                Button("Sound Settings…") { open("x-apple.systempreferences:com.apple.Sound-Settings.extension") }
                Button("Microphone Permission…") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }
                Button("System Audio Permission…") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }
            } header: { Text("Devices and permissions") } footer: {
                caption("Voice Isolation is Apple’s noise removal for your microphone. macOS lets you switch it while a recording is running: use Change… or the ⋯ menu in the menu bar. Colleagues are recorded with “System Audio Recording Only”; screen recording is never needed.")
            }
        }
    }
    var micMode: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: return "Voice Isolation"
        case .wideSpectrum: return "Wide Spectrum"
        default: return "Standard"
        }
    }
    func dot(_ color: Color) -> some View { Circle().fill(color).frame(width: 8, height: 8) }
    func source(microphone: Bool) -> Binding<Bool> {
        Binding(
            get: { microphone ? state.preferences.source.usesMicrophone : state.preferences.source.usesSystemAudio },
            set: { value in
                let current = state.preferences.source
                if let next = microphone ? AudioSource.from(microphone: value, system: current.usesSystemAudio) : AudioSource.from(microphone: current.usesMicrophone, system: value) { state.preferences.source = next }
            })
    }
    func open(_ string: String) { if let url = URL(string: string) { NSWorkspace.shared.open(url) } }
}

struct TranscriptionSettings: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section {
                ForEach(ASRModel.allCases.reversed()) { model in
                    Button { state.preferences.model = model } label: {
                        HStack(spacing: 10) {
                            Image(systemName: state.preferences.model == model ? "largecircle.fill.circle" : "circle").foregroundStyle(state.preferences.model == model ? Theme.orange : Theme.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.label)
                                caption(model == .best ? "Most accurate, especially for quiet voices and switching languages." : model == .large ? "Nearly as accurate, uses less memory." : "Quickest, lightest, least accurate.")
                            }
                            Spacer()
                            if state.engine.ready(model) { MonoLabel("Installed", color: Theme.secondary) } else { MonoLabel(model.size) }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(state.engine.busy)
                }
                if state.engine.busy && state.processingID == nil {
                    ProgressView(value: state.engine.fraction) { Text(state.engine.message).font(.caption) }.tint(Theme.orange)
                    Button("Cancel Download") { state.cancelProcessing() }
                } else if !state.engine.ready(state.preferences.model) {
                    Button("Download \(state.preferences.model.shortLabel) (\(state.preferences.model.size))") { state.runOperation { await state.installModels() } }
                        .buttonStyle(ControlStyle(kind: .primary)).disabled(state.operationTask != nil)
                }
            } header: { Text("Speech model") } footer: {
                caption("Qwen3-ASR runs entirely on this Mac. Audio never leaves it. The first download also installs a private runtime.")
            }
            Section {
                FlowLayout(spacing: 6) {
                    ForEach(shownLanguages, id: \.self) { language in
                        ToggleChip(title: language, isOn: Binding(
                            get: { state.preferences.languages.contains(language) },
                            set: { on in
                                if on { state.preferences.languages.append(language) } else { state.preferences.languages.removeAll { $0 == language } }
                            }))
                    }
                    Menu {
                        ForEach(Preferences.supportedLanguages.filter { !shownLanguages.contains($0) }, id: \.self) { language in
                            Button(language) { state.preferences.languages.append(language) }
                        }
                    } label: { Text("More…").font(.system(size: 12)) }
                    .menuStyle(.button).buttonStyle(ControlStyle(kind: .quiet, compact: true)).menuIndicator(.hidden).fixedSize()
                }
                .padding(.vertical, 4)
                LabeledContent("Recognized as") {
                    Text(languageSummary).foregroundStyle(Theme.secondary)
                }
            } header: { Text("Languages spoken in your meetings") } footer: {
                caption("Pick only the languages people actually speak, for example English and Arabic. Short sounds then can’t be mistaken for Chinese or Hindi, and people can still switch languages sentence by sentence. Dialects such as Saudi Arabic are recognized as Arabic. Leave everything off to detect any language.")
            }
            Section {
                TextField("Names and terms", text: $state.preferences.vocabulary, prompt: Text("Ashref, Kubernetes, Q3 roadmap"), axis: .vertical).lineLimit(2...4)
            } header: { Text("Spelling") } footer: {
                caption("Names, products and jargon, separated by commas. Keep it to words: sentences here can confuse recognition.")
            }
        }
    }
    static let common = ["English", "Arabic", "French", "Spanish", "German", "Italian", "Portuguese", "Turkish", "Hindi", "Chinese", "Japanese", "Korean"]
    var shownLanguages: [String] { Self.common + state.preferences.languages.filter { !Self.common.contains($0) } }
    var languageSummary: String {
        switch state.preferences.languages.count {
        case 0: return "Any of 30 languages"
        case 1: return "\(state.preferences.languages[0]) only"
        default: return state.preferences.languages.formatted(.list(type: .or))
        }
    }
}

struct StorageSettings: View {
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section {
                Picker("Delete audio after", selection: $state.preferences.retentionDays) {
                    Text("Never").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
            } header: { Text("Audio") } footer: {
                caption("Only audio of transcribed meetings is deleted. Transcripts and notes are kept. Failed or incomplete recordings are always kept.")
            }
            Section {
                LabeledContent("Library") { Text(state.library.root.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).lineLimit(2) }
                Button("Show in Finder") { NSWorkspace.shared.open(state.library.root) }
            } footer: { caption("Everything stays on this Mac. Use FileVault for encryption, and keep this folder out of cloud sync if you want it fully local.") }
        }
    }
}
