import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 208)
                .floatingSidebar(Theme.background)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: state.settingsPane.symbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Theme.orange)
                            .frame(width: 24)
                        Text(state.settingsPane.title)
                            .font(.system(size: 20, weight: .semibold))
                    }
                    Group {
                        switch state.settingsPane {
                        case .general: GeneralSettings(state: state)
                        case .recording: RecordingSettings(state: state)
                        case .transcription: TranscriptionSettings(state: state)
                        case .analysis: AnalysisSettings(state: state)
                        case .storage: StorageSettings(state: state)
                        case .credits: CreditsSettings(state: state)
                        }
                    }
                }
                .id(state.settingsPane)
                .transition(reduceMotion ? .identity : .opacity.animation(Theme.feedback))
                .frame(maxWidth: 540)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .top)
                .thinScrollbars()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 520)
        .onChange(of: state.preferences) { _, _ in state.savePreferences() }
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                LogoMark(size: 13)
                Text("Settings").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 12)
            ForEach(SettingsPane.allCases) { pane in
                Button { withAnimation(reduceMotion ? nil : Theme.selection) { state.settingsPane = pane } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: pane.symbol).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(state.settingsPane == pane ? Theme.orange : Theme.secondary).frame(width: 18)
                        Text(pane.title).font(.system(size: 13, weight: state.settingsPane == pane ? .semibold : .regular))
                        Spacer()
                    }
                    .padding(.horizontal, 8).frame(height: Theme.controlHeight)
                }
                .buttonStyle(RowStyle(selected: state.settingsPane == pane))
                .focusEffectDisabled()
                .accessibilityAddTraits(state.settingsPane == pane ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
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
            MonoLabel(title).padding(.leading, 4)
            VStack(spacing: 0) { content }.card()
            if let footer {
                Text(footer).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 24)
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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 40)
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
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 12) }
}

private func openURL(_ string: String) { if let url = URL(string: string) { NSWorkspace.shared.open(url) } }

// MARK: Panes

struct GeneralSettings: View {
    @ObservedObject var state: AppState
    static let shortcuts: [(String, [String])] = [
        ("Start or stop from any app", GlobalHotKey.keys), ("Start recording", ["⌘", "N"]), ("Pause or resume", ["⌘", "⇧", "P"]), ("Stop and transcribe", ["⌘", "⇧", "S"]),
        ("Meeting library", ["⌘", "L"]), ("Search meetings", ["⌘", "F"]), ("Previous or next meeting", ["↑", "↓"]), ("Move meeting to Trash", ["⌫"]), ("Play or pause a meeting", ["Space"]), ("Transcript, AI notes, My notes", ["⌘", "1–3"]),
        ("Copy the open tab", ["⌘", "⇧", "C"]), ("Export as Markdown", ["⌘", "⇧", "E"]), ("Toggle sidebar", ["⌃", "⌘", "S"]), ("Import audio", ["⌘", "O"]), ("Settings", ["⌘", ","])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "App") {
                SettingsRow(title: "Appearance") {
                    Segmented(options: [("system", "System"), ("light", "Light"), ("dark", "Dark")], selection: $state.preferences.appearance)
                }
                RowDivider()
                SettingsToggle(title: "Open at login", detail: "Starts quietly in the menu bar.", isOn: Binding(get: { state.preferences.launchAtLogin }, set: { state.setLogin($0) }))
                RowDivider()
                SettingsToggle(title: "Notify when a transcript is ready", detail: "Only while you’re in another app.", isOn: Binding(get: { state.preferences.notifyWhenReady }, set: { on in
                    state.preferences.notifyWhenReady = on
                    if on { Task { await Notifier.requestPermission() } }
                }))
                if SMAppService.mainApp.status == .requiresApproval {
                    RowDivider()
                    SettingsRow(title: "Needs your approval", detail: "macOS asks before apps open at login.") {
                        Button("Login Items…") { SMAppService.openSystemSettingsLoginItems() }.buttonStyle(ControlStyle(compact: true))
                    }
                }
            }
            SettingsSection(title: "Keyboard", footer: "Left-click the menu bar icon for the recorder, right-click for quick actions.") {
                SettingsToggle(title: "Start or stop from any app", detail: "Control-Option-Command-R works even when Ultra Transcribe is in the background.", isOn: $state.preferences.globalShortcut)
                RowDivider()
                ForEach(Array(Self.shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    if index > 0 { RowDivider() }
                    SettingsRow(title: shortcut.0) { KeyCaps(keys: shortcut.1) }
                }
            }
            SettingsSection(title: "Setup") {
                SettingsRow(title: "First-run setup", detail: "Permissions, speech model, languages and AI notes, step by step.") {
                    Button("Run Again…") { state.showSetup() }.buttonStyle(ControlStyle(compact: true))
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
    @State private var inputs: [AudioDevice] = []
    var automatic: AudioDevice? { AudioDevice.microphone(preferred: nil, among: inputs, defaultID: AudioDevice.defaultDevice(input: true)) }
    var chosen: AudioDevice? { inputs.first { $0.uid == state.preferences.microphone } }
    var microphoneTitle: String {
        if let chosen { return chosen.name }
        if state.preferences.microphone != nil { return "Not connected" }
        return automatic.map { "Automatic · \($0.name)" } ?? "No microphone"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Record by default", footer: "Separate tracks let transcripts and AI notes tell who said what. Headphones keep colleagues out of your microphone.") {
                SourcePicker(state: state).padding(12)
            }
            SettingsSection(title: "Microphone", footer: "Automatic never opens a Bluetooth headset’s microphone, which would switch it to muffled call quality. Your Mac’s microphone records you instead.") {
                SettingsRow(title: "Records You", detail: chosen?.isBluetooth == true ? "Bluetooth: your headset plays in call quality while you record." : nil) {
                    Menu {
                        Button { state.preferences.microphone = nil } label: { choice(automatic.map { "Automatic (\($0.name))" } ?? "Automatic", on: state.preferences.microphone == nil) }
                        Divider()
                        ForEach(inputs) { device in
                            Button { state.preferences.microphone = device.uid } label: { choice(device.isBluetooth ? "\(device.name) (call quality)" : device.name, on: state.preferences.microphone == device.uid) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic").font(.system(size: 10))
                            Text(microphoneTitle)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.6)
                        }
                    }
                    .menuStyle(.button).buttonStyle(ControlStyle(compact: true)).menuIndicator(.hidden).fixedSize()
                    .help("Microphone that records you")
                }
            }
            .onAppear { inputs = AudioDevice.inputs() }
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

@ViewBuilder private func choice(_ title: String, on: Bool) -> some View {
    if on { Label(title, systemImage: "checkmark") } else { Text(title) }
}

struct TranscriptionSettings: View {
    @ObservedObject var state: AppState
    let memory = ProcessInfo.processInfo.physicalMemory
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(title: "Speech model", footer: "Everything runs on this Mac (\(Int((Double(memory) / 1_073_741_824).rounded())) GB memory), and memory is used only while transcribing. Times and memory are measured on a one-minute meeting, loading included.") {
                SpeechModelList(state: state)
            }
            SettingsSection(title: "While recording") {
                SettingsToggle(title: "Transcribe while recording", detail: "The transcript is ready seconds after you stop, and you can follow it live. Keeps the speech model in memory during meetings.", isOn: $state.preferences.liveTranscription)
            }
            SettingsSection(title: "Languages spoken", footer: LanguageChips.summary(state.preferences)) {
                LanguageChips(state: state).padding(12)
            }
            SettingsSection(title: "Names and terms", footer: "Comma-separated names, products and jargon. Words only: sentences here can confuse recognition. Qwen3-ASR and Whisper use them. Correcting a line in a transcript offers to add new names here.") {
                TextField("", text: $state.preferences.vocabulary, prompt: Text("Achraf, Kubernetes, Q3 roadmap"), axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...4).focusEffectDisabled().padding(12)
            }
        }
    }
}

/// The local speech models with what each is good at, its cost, and download or delete. Setup shows only `models`
/// and offers the download as its main button instead of per-row actions.
struct SpeechModelList: View {
    @ObservedObject var state: AppState
    var models = ASRModel.allCases
    var offersActions = true
    @State private var deleting: ASRModel?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var recommended: ASRModel { ASRModel.recommended(forMemory: ProcessInfo.processInfo.physicalMemory) }
    var body: some View {
        ForEach(Array(models.enumerated()), id: \.element) { index, model in
            if index > 0 { RowDivider() }
            if model == .whisperTurbo && offersActions {
                MonoLabel("More models").frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            }
            row(model)
            if state.engine.downloading == model {
                VStack(alignment: .leading, spacing: 8) {
                    DotProgress(value: state.engine.fraction, dots: 40).frame(height: 6)
                    HStack {
                        Text(state.engine.message).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        Spacer()
                        Button("Cancel") { state.cancelProcessing() }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 12).padding(.leading, 28)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : Theme.selection, value: state.engine.downloading)
        .confirmationDialog("Delete \(deleting?.name ?? "this model")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete", role: .destructive) { if let deleting { state.deleteModel(deleting) }; deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This frees \(deleting?.size ?? "its space") on this Mac. Transcripts are kept, and you can download the model again.") }
    }
    func row(_ model: ASRModel) -> some View {
        let selected = state.preferences.model == model
        let installed = state.engine.ready(model)
        return HStack(alignment: .center, spacing: 12) {
            Button { withAnimation(reduceMotion ? nil : Theme.feedback) { state.preferences.model = model } } label: {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle().strokeBorder(selected ? Theme.orange : Theme.secondary.opacity(0.4), lineWidth: 1.5).frame(width: 16, height: 16)
                        if selected { Circle().fill(Theme.orange).frame(width: 8, height: 8).transition(reduceMotion ? .identity : .scale) }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(model.name).font(.system(size: 13, weight: selected ? .semibold : .regular))
                            if model == recommended {
                                Text("Recommended").font(.system(size: 9.5, weight: .semibold, design: .monospaced)).textCase(.uppercase)
                                    .foregroundStyle(Theme.orange).padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Theme.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                            }
                        }
                        Text("\(model.maker) · \(Self.languageLine(model))").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        Text("\(model.size) download · \(String(format: "%.1f", model.memoryGB)) GB memory · 1 min in \(model.minuteSeconds) s")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.secondary.opacity(0.85))
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityHint(installed ? "Installed" : "Not downloaded")
            if offersActions && installed {
                MonoLabel("Installed")
                Button { deleting = model } label: { Image(systemName: "trash").font(.system(size: 11, weight: .semibold)) }
                    .buttonStyle(ControlStyle(kind: .quiet, compact: true, square: true))
                    .help("Delete \(model.name)").accessibilityLabel("Delete \(model.name)")
            } else if offersActions {
                Button("Download") { state.runOperation { await state.install(model) } }
                    .buttonStyle(ControlStyle(kind: selected ? .primary : .secondary, compact: true))
                    .disabled(state.operationTask != nil)
            } else {
                MonoLabel(installed ? "Installed" : model.size)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .disabled(state.engine.busy)
    }
    static func languageLine(_ model: ASRModel) -> String {
        let count = model.languages.count == 2 ? model.languages.formatted(.list(type: .and)) : "\(model.languages.count) languages"
        switch model.languageMode {
        case .several: return "\(count), mixed freely"
        case .one: return "\(count), one at a time"
        case .automatic: return "\(count), detected automatically"
        }
    }
}

/// Language toggles for the selected model: the common ones it knows, any already chosen, the rest behind More.
/// One-language models treat the chips as a single choice; models that detect the language list what they know.
struct LanguageChips: View {
    @ObservedObject var state: AppState
    static let common = ["English", "Arabic", "French", "Spanish", "German", "Italian", "Portuguese", "Turkish", "Hindi", "Chinese", "Japanese", "Korean"]
    var model: ASRModel { state.preferences.model }
    var shown: [String] {
        let supported = model.languages
        return Self.common.filter(supported.contains) + state.preferences.languages.filter { supported.contains($0) && !Self.common.contains($0) }
    }
    var body: some View {
        if model.languageMode == .automatic {
            Text(model.languages.formatted(.list(type: .and)))
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        } else {
            FlowLayout(spacing: 6) {
                ForEach(shown, id: \.self) { language in
                    ToggleChip(title: language, isOn: Binding(get: { isOn(language) }, set: { set(language, on: $0) }))
                }
                let rest = model.languages.filter { !shown.contains($0) }
                if !rest.isEmpty {
                    Menu {
                        ForEach(rest, id: \.self) { language in Button(language) { set(language, on: true) } }
                    } label: { HStack(spacing: 4) { Text("More"); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) } }
                    .menuStyle(.button).buttonStyle(ControlStyle(kind: .quiet, compact: true)).menuIndicator(.hidden).fixedSize()
                }
            }
        }
    }
    func isOn(_ language: String) -> Bool {
        model.languageMode == .one ? state.preferences.spokenLanguages.first == language : state.preferences.languages.contains(language)
    }
    /// Choices are kept across models: picking a language for a one-language model moves it to the front.
    func set(_ language: String, on: Bool) {
        if model.languageMode == .one {
            guard on else { return }
            state.preferences.languages.removeAll { $0 == language }
            state.preferences.languages.insert(language, at: 0)
        } else if on {
            if !state.preferences.languages.contains(language) { state.preferences.languages.append(language) }
        } else {
            state.preferences.languages.removeAll { $0 == language }
        }
    }
    static func summary(_ preferences: Preferences) -> String {
        let model = preferences.model
        let spoken = preferences.spokenLanguages
        let unsupported = preferences.languages.filter { !model.languages.contains($0) }
        let missing = unsupported.formatted(.list(type: .and))
        let note = unsupported.isEmpty ? "" : " \(model.name) doesn’t support \(missing)."
        switch model.languageMode {
        case .automatic:
            return "\(model.name) detects the language of each sentence by itself" + (unsupported.isEmpty ? "." : ", and doesn’t support \(missing).")
        case .one:
            return spoken.first.map { "Everything is transcribed as \($0). \(model.name) transcribes one language per meeting." }
                ?? "Choose the language people speak: \(model.name) transcribes one language per meeting."
        case .several:
            let base = switch spoken.count {
            case 0: "Any of \(model.languages.count) languages is detected."
            case 1: "Everything is transcribed as \(spoken[0])."
            default: "Each sentence is recognized as \(spoken.formatted(.list(type: .or)))."
            }
            return base + note + " Choose only the languages people speak, so short sounds can’t be mistaken for other languages. Dialects such as Saudi Arabic count as Arabic."
        }
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
    @ObservedObject var state: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let icon = LogoGlyph.appIcon(size: 192)
    static let website = URL(string: "https://ultra.achraf.tn")!
    static let author = URL(string: "https://achraf.tn")!
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    @State private var hovering = false
    var updater: Updater { state.updater }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: Self.icon).resizable().frame(width: 96, height: 96)
                    .scaleEffect(reduceMotion || !hovering ? 1 : 1.04).animation(reduceMotion ? nil : .snappy(duration: 0.25), value: hovering)
                    .onHover { hovering = $0 }
                    .accessibilityHidden(true)
                Text("Ultra Transcribe").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                MonoLabel("Version \(version)\(build.map { " (\($0))" } ?? "")")
                Text("Private meeting transcripts from your menu bar.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8).padding(.bottom, 24)
            SettingsSection(title: "Updates", footer: "Checks read the public release list on GitHub. Nothing about you or your meetings is sent. Installing moves this copy to the Trash and relaunches.") {
                updateRow
                if case .available(let release) = updater.state, let notes = release.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
                    RowDivider()
                    Text(notes).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(10).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                RowDivider()
                SettingsToggle(title: "Check automatically", detail: "Once a day; tells you when a new version is out.", isOn: $state.preferences.checkForUpdates)
            }
            .animation(reduceMotion ? nil : Theme.feedback, value: updater.state)
            SettingsSection(title: "Links") {
                SettingsRow(title: "Website", detail: "ultra.achraf.tn") {
                    Link(destination: Self.website) { LinkLabel("Open") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "Made by", detail: "achraf.tn") {
                    Link(destination: Self.author) { LinkLabel("Open") }.buttonStyle(ControlStyle(compact: true))
                }
                RowDivider()
                SettingsRow(title: "All releases", detail: "github.com/Ashref-dev/ultra-meet-v2") {
                    Link(destination: Updater.releasesPage) { LinkLabel("Open") }.buttonStyle(ControlStyle(compact: true))
                }
            }
            SettingsSection(title: "Built with", footer: "Speech recognition runs locally on MLX through mlx-audio, with the speech model you choose. AI analysis uses OpenRouter, only when you ask.") {
                HStack(spacing: 6) {
                    ForEach(["Qwen3-ASR", "MLX", "mlx-audio", "OpenRouter", "SwiftUI"], id: \.self) { name in
                        Text(name).font(.system(size: 11.5, weight: .medium)).padding(.horizontal, 8).frame(height: 20)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
            }
        }
    }
    @ViewBuilder var updateRow: some View {
        switch updater.state {
        case .idle:
            SettingsRow(title: "Version \(version)", detail: "Look for a newer version on GitHub.") { checkButton("Check Now") }
        case .checking:
            SettingsRow(title: "Checking for updates…") { DotProgress(value: nil, dots: 10).frame(width: 50, height: 5) }
        case .current(let date):
            SettingsRow(title: "You’re up to date", detail: "Version \(version) · checked \(date.formatted(.relative(presentation: .named)))") { checkButton("Check Again") }
        case .available(let release):
            SettingsRow(title: "Version \(release.version?.description ?? release.tag) is available", detail: busy ? "Finish recording and transcribing first." : "You have \(version).") {
                HStack(spacing: 6) {
                    Link(destination: release.page) { LinkLabel("Notes") }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    Button(release.archive == nil ? "Download…" : "Install and Relaunch") { Task { await updater.install(release) { busy } } }
                        .buttonStyle(ControlStyle(kind: .primary, compact: true)).disabled(busy)
                }
            }
        case .installing(let step):
            SettingsRow(title: step, detail: "Ultra Transcribe relaunches when it’s done.") { DotProgress(value: nil, dots: 10).frame(width: 50, height: 5) }
        case .failed(let message):
            SettingsRow(title: "Update didn’t work", detail: message) {
                HStack(spacing: 6) {
                    Link(destination: Updater.releasesPage) { LinkLabel("GitHub") }.buttonStyle(ControlStyle(kind: .quiet, compact: true))
                    checkButton("Try Again")
                }
            }
        }
    }
    /// Installing quits the app, so it waits for recordings and transcriptions to finish.
    var busy: Bool { state.activeID != nil || state.isWorking || state.starting || state.analyzingID != nil }
    func checkButton(_ title: String) -> some View {
        Button(title) { Task { await updater.check() } }.buttonStyle(ControlStyle(compact: true))
    }
}
