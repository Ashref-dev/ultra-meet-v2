import AVFoundation
import SwiftUI

/// First-run setup: what the app does, both permissions with a live microphone check, the speech model and
/// languages, an optional OpenRouter key, then notifications and shortcuts. Every step can be skipped.
struct SetupView: View {
    @ObservedObject var state: AppState
    let finish: () -> Void
    @State private var step = 0
    @StateObject private var check = MicrophoneCheck()
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var macAudio: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let steps = ["Welcome", "You", "Colleagues", "Speech", "AI notes", "Ready"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LogoMark(size: 12)
                MonoLabel("Setup · \(Self.steps[step])")
                Spacer()
                HStack(spacing: 5) {
                    ForEach(Self.steps.indices, id: \.self) { index in
                        Capsule().fill(index <= step ? Theme.orange : Theme.line).frame(width: index == step ? 16 : 6, height: 6)
                    }
                }
                .animation(reduceMotion ? nil : Theme.selection, value: step)
                .accessibilityElement().accessibilityLabel("Step \(step + 1) of \(Self.steps.count)")
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 12)
            ScrollView {
                page
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 32).padding(.vertical, 12)
            }
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 18)), removal: .opacity))
            Divider()
            HStack(spacing: 8) {
                if step > 0 { Button("Back") { go(step - 1) }.buttonStyle(ControlStyle(kind: .quiet)) }
                else { Button("Skip Setup") { done() }.buttonStyle(ControlStyle(kind: .quiet)) }
                Spacer()
                Button(step == Self.steps.count - 1 ? "Start Using Ultra Transcribe" : step == 0 ? "Get Started" : "Continue") {
                    step == Self.steps.count - 1 ? done() : go(step + 1)
                }
                .buttonStyle(ControlStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 580, height: 560)
        .background(Theme.background)
        .tint(Theme.orange)
        .onChange(of: step) { _, value in if value == 1 && microphone == .authorized { check.start() } else { check.stop() } }
        .onDisappear { check.stop() }
    }

    @ViewBuilder var page: some View {
        switch step {
        case 0: welcome
        case 1: you
        case 2: colleagues
        case 3: speech
        case 4: notes
        default: ready
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(nsImage: LogoGlyph.appIcon(size: 160)).resizable().frame(width: 80, height: 80).accessibilityHidden(true)
            title("Welcome to Ultra Transcribe", "Meeting notes for the AI-native era, made on your Mac.")
            feature(AnyView(HStack(spacing: -6) { SpeakerAvatar(source: "microphone", size: 22); SpeakerAvatar(source: "system", size: 22) }), "You and your colleagues, on separate tracks", "Every line of the transcript says who spoke.")
            feature(AnyView(icon("lock.fill")), "Transcribed on this Mac", "Audio never leaves it. Quiet voices and whispers are picked up too.")
            feature(AnyView(icon("sparkles")), "Notes when you ask", "A summary, decisions and action items from the AI model you choose.")
            Text("Ultra Transcribe is built for consensual meetings. Let people know when you record.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        }
    }

    var you: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Your voice", "Your microphone is recorded as You, in green.")
            switch microphone {
            case .authorized:
                VStack(alignment: .leading, spacing: 10) {
                    DotWaveform(meter: check.meter, live: true).frame(height: 54)
                    Text(check.failure ?? "Say something. The dots should move with your voice.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                }
                .padding(14).card()
                Label("Microphone allowed", systemImage: "checkmark.circle.fill").font(.system(size: 12.5)).foregroundStyle(Theme.you)
            case .denied, .restricted:
                InlineHint(symbol: "mic.slash", text: "Microphone access is off. Turn on Ultra Transcribe in Privacy & Security → Microphone.", action: ("Open…", { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") }))
            default:
                Button { requestMicrophone() } label: { Label("Allow Microphone", systemImage: "mic.fill") }.buttonStyle(ControlStyle(kind: .primary))
                Text("macOS asks once. You can change it later in System Settings.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }

    var colleagues: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Your colleagues", "Call audio playing on this Mac is recorded as Colleagues, in orange. Ultra Transcribe never records your screen.")
            if let macAudio {
                Label(macAudio, systemImage: "checkmark.circle.fill").font(.system(size: 12.5)).foregroundStyle(Theme.colleagues)
                Button("Open Privacy Settings…") { open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") }.buttonStyle(ControlStyle(compact: true))
            } else {
                Button { requestMacAudio() } label: { Label("Allow Mac Audio", systemImage: "speaker.wave.2.fill") }.buttonStyle(ControlStyle(kind: .primary))
                Text("macOS asks for “System Audio Recording Only”. If you skip this, it asks at your first recording.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
            InlineHint(symbol: "headphones", text: "With headphones, colleagues never leak into your microphone, so who said what stays exact.")
        }
    }

    var speech: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("Speech recognition", "Pick a model for this Mac and the languages people speak. Transcription runs here, offline.")
            VStack(spacing: 0) { SpeechModelList(state: state) }.card()
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Languages spoken")
                LanguageChips(state: state)
                Text("Choose only the languages your meetings use, for example English, Arabic and French.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
            }
        }
    }

    var notes: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("AI notes, optional", "Analyze with AI sends the transcript text, never audio, to the OpenRouter model you choose. It needs a key from openrouter.ai.")
            VStack(spacing: 0) { OpenRouterKeyField(state: state) }.card()
            Text("You can add or change the key later in Settings → AI Analysis.").font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        }
    }

    var ready: some View {
        VStack(alignment: .leading, spacing: 16) {
            title("You’re ready", "Ultra Transcribe lives in the menu bar. Click its dots to record; right-click for quick actions.")
            VStack(spacing: 0) {
                SettingsToggle(title: "Notify me when a transcript is ready", detail: "Only while you’re in another app.", isOn: Binding(get: { state.preferences.notifyWhenReady }, set: { on in
                    state.preferences.notifyWhenReady = on
                    state.savePreferences()
                    if on { Task { await Notifier.requestPermission() } }
                }))
                RowDivider()
                SettingsToggle(title: "Open at login", detail: "Starts quietly in the menu bar.", isOn: Binding(get: { state.preferences.launchAtLogin }, set: { state.setLogin($0) }))
                RowDivider()
                SettingsToggle(title: "Check for updates automatically", detail: "Once a day, from GitHub.", isOn: Binding(get: { state.preferences.checkForUpdates }, set: { state.preferences.checkForUpdates = $0; state.savePreferences() }))
                RowDivider()
                SettingsRow(title: "Start or stop from any app") { KeyCaps(keys: GlobalHotKey.keys) }
            }
            .card()
        }
    }

    func title(_ heading: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(heading).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
            Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    func feature(_ symbol: AnyView, _ heading: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            symbol.frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(heading).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
        }
    }
    func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Theme.orange, in: Circle())
    }
    func go(_ target: Int) { withAnimation(reduceMotion ? nil : Theme.selection) { step = target } }
    func done() {
        check.stop()
        state.preferences.setupDone = true
        state.savePreferences()
        finish()
    }
    func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            if microphone == .authorized && step == 1 { check.start() }
        }
    }
    /// Starting a system audio capture for a moment is what makes macOS ask for permission.
    func requestMacAudio() {
        let tap = SystemAudioTap()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ultra-transcribe-permission-\(UUID().uuidString).caf")
        do {
            try tap.start(url: url)
            macAudio = "Asked. If macOS showed a prompt, choose Allow."
        } catch {
            macAudio = "macOS didn’t allow it yet. Turn on Ultra Transcribe under Screen & System Audio Recording → System Audio Recording Only."
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            tap.stop()
            try? FileManager.default.removeItem(at: url)
        }
    }
    func open(_ address: String) { if let url = URL(string: address) { NSWorkspace.shared.open(url) } }
}

/// A microphone level check for setup: meters the input into a temporary file that is deleted right away.
@MainActor
final class MicrophoneCheck: ObservableObject {
    let meter = LevelMeter()
    @Published var failure: String?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func start() {
        guard recorder == nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ultra-transcribe-mic-check.wav")
        do {
            let input = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1])
            input.isMeteringEnabled = true
            guard input.record() else { throw AppError.message("The microphone could not start. Check your input in System Settings → Sound.") }
            recorder = input
            failure = nil
        } catch {
            failure = error.localizedDescription
            return
        }
        timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.meter.push(.init(you: LevelMeter.normalized(decibels: recorder.averagePower(forChannel: 0)), colleagues: 0), interval: 0.08)
            }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder?.deleteRecording()
        recorder = nil
        meter.reset()
    }
}
