import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 196).background(Theme.background.ignoresSafeArea())
            Divider().ignoresSafeArea()
            ScrollView {
                Group {
                    switch state.settingsPane {
                    case .general: GeneralSettings(state: state)
                    case .recording: RecordingSettings(state: state)
                    case .transcription: TranscriptionSettings(state: state)
                    case .analysis: AnalysisSettings(state: state)
                    case .storage: StorageSettings(state: state)
                    case .credits: CreditsSettings()
                    }
                }
                .id(state.settingsPane)
                .transition(.opacity.animation(.easeOut(duration: 0.14)))
                .frame(maxWidth: 540)
                .padding(.horizontal, 32).padding(.vertical, 26)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.paper.ignoresSafeArea())
        }
        .tint(Theme.orange)
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: state.preferences) { _, _ in state.savePreferences() }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                LogoMark(size: 13)
                Text("Settings").font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 14)
            ForEach(SettingsPane.allCases) { pane in
                Button { withAnimation(Theme.selection) { state.settingsPane = pane } } label: {
                    HStack(spacing: 9) {
                        Image(systemName: pane.symbol).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(state.settingsPane == pane ? Theme.orange : Theme.secondary).frame(width: 18)
                        Text(pane.title).font(.system(size: 13, weight: state.settingsPane == pane ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 10).frame(height: 30).contentShape(Rectangle())
                }
                .buttonStyle(RowStyle(selected: state.settingsPane == pane))
                .accessibilityAddTraits(state.settingsPane == pane ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 10)
    }
}

// MARK: Building blocks

/// Titled card of rows with an optional footnote.
struct SettingsSection<Content: View>: View {
    let title: String
    var footer: String?
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(title).padding(.leading, 2)
            VStack(spacing: 0) { content }.card()
            if let footer {
                Text(footer).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
            }
        }
        .padding(.bottom, 22)
    }
}

/// Label on the left, control on the right; dividers are added by the caller.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let accessory: Accessory
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

/// A whole row that toggles, with the shared switch.
struct SettingsToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            SettingsRow(title: title, detail: detail) { SwitchKnob(isOn: isOn) }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

private func openURL(_ string: String) { if let url = URL(string: string) { NSWorkspace.shared.open(url) } }

// MARK: Panes

struct GeneralSettings: View {
    @ObservedObject var state: AppState
    static let shortcuts: [(String, [String])] = [
        ("Start recording", ["⌘", "N"]), ("Pause or resume", ["⌘", "⇧", "P"]), ("Stop and transcribe", ["⌘", "⇧", "S"]),
        ("Meeting library", ["⌘", "L"]), ("Toggle sidebar", ["⌃", "⌘", "S"]), ("Import audio", ["⌘", "O"]), ("Settings", ["⌘", ","])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "App") {
                SettingsRow(title: "Appearance") {
                    Segmented(options: [("system", "System"), ("light", "Light"), ("dark", "Dark")], selection: $state.preferences.appearance)
                }
                RowDivider()
                SettingsToggle(title: "Open at login", detail: "Starts quietly in the menu bar.", isOn: Binding(get: { state.preferences.launchAtLogin }, set: { state.setLogin($0) }))
                if SMAppService.mainApp.status == .requiresApproval {
                    RowDivider()
                    SettingsRow(title: "Needs your approval", detail: "macOS asks before apps open at login.") {
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(ControlStyle(compact: true))
                    }
                }
            }
            SettingsSection(title: "Keyboard", footer: "Left-click the menu bar icon for the recorder, right-click for quick actions.") {
                ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    if index > 0 { RowDivider() }
                    HStack {
                        Text(shortcut.0).font(.system(size: 13))
                        Spacer()
                        KeyCaps(keys: shortcut.1)
                    }
                    .padding(.horizontal, 14).frame(height: 36)
                }
            }
        }
        .onAppear { state.refreshLoginStatus() }
    }
}

struct RecordingSettings: View {
    @ObservedObject var state: AppState
    var microphonePermission: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Not allowed"
        default: return "Asks on first recording"
        }
    }
    var micMode: String {
        switch AVCaptureDevice.activeMicrophoneMode {
        case .voiceIsolation: return "Voice Isolation"
        case .wideSpectrum: return "Wide Spectrum"
        default: return "Standard"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Record by default", footer: "Separate tracks let transcripts and AI notes tell who said what. Headphones keep colleagues out of your microphone.") {
                HStack { SourcePicker(state: state); Spacer() }.padding(12)
            }
            SettingsSection(title: "Microphone", footer: "Voice Isolation removes background voices and noise. macOS lets you switch it while a recording is running.") {
                SettingsRow(title: "Input", detail: AVCaptureDevice.default(for: .audio)?.localizedName ?? "No input device") {
                    Button("Sound…") { openURL("x-apple.systempreferences:com.apple.Sound-Settings.extension") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "Mic mode", detail: micMode) {
                    Button("Change…") { AVCaptureDevice.showSystemUserInterface(.microphoneModes) }.buttonStyle(ControlStyle(compact: true))
                }
            }
            SettingsSection(title: "Permissions") {
                SettingsRow(title: "Microphone", detail: microphonePermission) {
                    Button("Open…") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "Mac audio", detail: "System Audio Recording Only. Screen recording is never needed.") {
                    Button("Open…") { openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }.buttonStyle(ControlStyle(compact: true))
                }
            }
        }
    }
}

struct TranscriptionSettings: View {
    @ObservedObject var state: AppState
    static let common = ["English", "Arabic", "French", "Spanish", "German", "Italian", "Portuguese", "Turkish", "Hindi", "Chinese", "Japanese", "Korean"]
    let memory = ProcessInfo.processInfo.physicalMemory
    var recommended: ASRModel { ASRModel.recommended(forMemory: memory) }
    var shownLanguages: [String] { Self.common + state.preferences.languages.filter { !Self.common.contains($0) } }
    var languageSummary: String {
        switch state.preferences.languages.count {
        case 0: return "Any of 30 languages is detected."
        case 1: return "Everything is transcribed as \(state.preferences.languages[0])."
        default: return "Each sentence is recognized as \(state.preferences.languages.formatted(.list(type: .or)))."
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Speech model", footer: "Runs entirely on this Mac (\(Int((Double(memory) / 1_073_741_824).rounded())) GB memory). Memory is only used while a meeting is being transcribed.") {
                ForEach(Array(ASRModel.allCases.reversed().enumerated()), id: \.element) { index, model in
                    if index > 0 { RowDivider() }
                    modelRow(model)
                }
                if state.engine.busy && state.processingID == nil {
                    RowDivider()
                    VStack(alignment: .leading, spacing: 8) {
                        DotProgress(value: state.engine.fraction, dots: 40).frame(height: 6)
                        HStack {
                            Text(state.engine.message).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                            Spacer()
                            Button("Cancel") { state.cancelProcessing() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                        }
                    }
                    .padding(14)
                } else if !state.engine.ready(state.preferences.model) {
                    RowDivider()
                    SettingsRow(title: "\(state.preferences.model.shortLabel) isn’t installed", detail: "\(state.preferences.model.size) download, one time.") {
                        Button("Download") { state.runOperation { await state.installModels() } }
                            .buttonStyle(ControlStyle(kind: .primary, compact: true)).disabled(state.operationTask != nil)
                    }
                }
            }
            SettingsSection(title: "Languages spoken", footer: "\(languageSummary) Choose only the languages people speak, so short sounds can’t be mistaken for other languages. Dialects such as Saudi Arabic count as Arabic.") {
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
                    } label: { HStack(spacing: 4) { Text("More"); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) } }
                    .menuStyle(.button).buttonStyle(ControlStyle(kind: .quiet, compact: true)).menuIndicator(.hidden).fixedSize()
                }
                .padding(12)
            }
            SettingsSection(title: "Names and terms", footer: "Comma-separated names, products and jargon. Words only: sentences here can confuse recognition.") {
                TextField("", text: $state.preferences.vocabulary, prompt: Text("Achraf, Kubernetes, Q3 roadmap"), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4).padding(14)
            }
        }
    }
    func modelRow(_ model: ASRModel) -> some View {
        let selected = state.preferences.model == model
        return Button { withAnimation(Theme.feedback) { state.preferences.model = model } } label: {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Theme.orange : Theme.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 16, height: 16)
                    if selected { Circle().fill(Theme.orange).frame(width: 8, height: 8).transition(.scale) }
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(model.label).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        if model == recommended {
                            Text("Recommended").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).textCase(.uppercase)
                                .foregroundStyle(Theme.orange).padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                        }
                    }
                    Text("≈ \(model.memoryGB.formatted(.number.precision(.fractionLength(1)))) GB memory · \(model.speed)× real time").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
                Spacer()
                MonoLabel(state.engine.ready(model) ? "Installed" : model.size)
            }
            .padding(.horizontal, 14).padding(.vertical, 11).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.engine.busy)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

struct StorageSettings: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Audio", footer: "Only audio of transcribed meetings is deleted. Transcripts and notes are kept, and incomplete recordings are never removed.") {
                SettingsRow(title: "Delete audio after") {
                    Segmented(options: [(0, "Never"), (1, "1 d"), (7, "7 d"), (14, "14 d"), (30, "30 d"), (90, "90 d")], selection: $state.preferences.retentionDays)
                }
            }
            SettingsSection(title: "Library", footer: "Everything stays on this Mac. Use FileVault for encryption, and keep this folder out of cloud sync.") {
                SettingsRow(title: "Location", detail: state.library.root.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                    Button("Show in Finder") { NSWorkspace.shared.open(state.library.root) }.buttonStyle(ControlStyle(compact: true))
                }
            }
        }
    }
}

struct CreditsSettings: View {
    private static let icon = LogoGlyph.appIcon(size: 192)
    static let website = URL(string: "https://ultra.achraf.tn")!
    static let author = URL(string: "https://achraf.tn")!
    /// Releases are published on GitHub; an in-app checker against the Releases API is the next step (see AGENTS.md).
    static let updates = URL(string: "https://github.com/Ashref-dev/ultra-meet-v2/releases")!
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    @State private var hovering = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: Self.icon).resizable().frame(width: 96, height: 96)
                    .scaleEffect(hovering ? 1.04 : 1).animation(.snappy(duration: 0.25), value: hovering)
                    .onHover { hovering = $0 }
                    .accessibilityHidden(true)
                Text("Ultra Transcribe").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                MonoLabel("Version \(version)\(build.map { " (\($0))" } ?? "")")
                Text("Private meeting transcripts from your menu bar.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8).padding(.bottom, 26)
            SettingsSection(title: "Links") {
                SettingsRow(title: "Website", detail: "ultra.achraf.tn") {
                    Link(destination: Self.website) { linkLabel("Open") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "Made by", detail: "achraf.tn") {
                    Link(destination: Self.author) { linkLabel("Open") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "Updates", detail: "You’re on version \(version).") {
                    Link(destination: Self.updates) { linkLabel("Check for Updates") }.buttonStyle(ControlStyle(kind: .primary, compact: true))
                }
            }
            SettingsSection(title: "Built with", footer: "Speech recognition runs locally with Qwen3-ASR on MLX through mlx-audio. AI analysis uses OpenRouter, only when you ask.") {
                HStack(spacing: 6) {
                    ForEach(["Qwen3-ASR", "MLX", "mlx-audio", "OpenRouter", "SwiftUI"], id: \.self) { name in
                        Text(name).font(.system(size: 11.5, weight: .medium)).padding(.horizontal, 8).frame(height: 22)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }
    func linkLabel(_ title: String) -> some View {
        HStack(spacing: 4) { Text(title); Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .bold)) }
    }
}
