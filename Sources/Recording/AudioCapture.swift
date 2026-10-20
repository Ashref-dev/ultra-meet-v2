import AVFoundation
import CoreAudio

/// Records one side of a meeting, Mac audio or the microphone, through Core Audio into a 16-bit, 48 kHz mono CAF.
///
/// Both sides share one timeline: they start from the same moment, and real interruptions (a device switch, a
/// stalled device) are filled with silence. Capture follows the hardware: switching speakers or headphones, or
/// connecting a microphone, moves the recording to the new device instead of losing the rest of the meeting.
final class AudioCapture: @unchecked Sendable {
    enum Source: Equatable {
        case system
        /// The microphone chosen in Settings (a device UID), or nil for automatic; see `AudioDevice.microphone`.
        case microphone(preferred: String?)
    }
    static let fileRate: Double = 48000
    let source: Source
    var onError: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var captureFailure: String? { queue.sync { storedFailure } }

    private let queue = DispatchQueue(label: "tn.achraf.ultratranscribe.capture", qos: .userInitiated)
    private var tap: AudioObjectID = 0
    private var tapUID = ""
    /// The device the recorder runs on: a private aggregate holding the tap, or the microphone itself.
    private var device: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var outputUID: String?
    private var ioProc: AudioDeviceIOProcID?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var routeListener: AudioObjectPropertyListenerBlock?
    // Touched on `queue` only.
    private var file: AVAudioFile?
    private var silence: AVAudioPCMBuffer?
    private var paused = false
    private var reportedError = false
    private var storedFailure: String?
    private var clock = RecordingClock()
    /// Buffers arrive at the device's rate, which differs between devices (44.1 kHz headphones, 16 or 24 kHz
    /// Bluetooth in a call) and can change mid-recording, so they are converted to the file's 48 kHz.
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(_ source: Source) { self.source = source }

    /// Starts recording to `url`. `started` is the shared start of the meeting, in host-time seconds.
    func start(url: URL, started: Double = AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())) throws {
        do {
            if source == .system { try makeTap() }
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.fileRate, AVNumberOfChannelsKey: 1,
                                           AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
            let output = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let silent = AVAudioPCMBuffer(pcmFormat: output.processingFormat, frameCapacity: AVAudioFrameCount(Self.fileRate)) else {
                throw AppError.message("Could not allocate the audio timeline buffer.")
            }
            silent.frameLength = silent.frameCapacity // new buffers are zeroed
            queue.sync {
                file = output
                silence = silent
                clock = RecordingClock(started: started)
            }
            try open()
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reroute() }
            for selector in routeSelectors {
                var address = Self.address(selector)
                _ = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            }
            routeListener = listener
        } catch { stop(); throw error }
    }
    func setPaused(_ value: Bool) {
        queue.sync {
            let now = AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())
            if value { clock.pause(now: now) } else { clock.resume(now: now) }
            paused = value
        }
    }
    func stop() {
        if let routeListener {
            for selector in routeSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, routeListener)
            }
            self.routeListener = nil
        }
        close()
        queue.sync {
            if let file, !reportedError {
                do { try pad(file, until: AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime()), tolerance: 0) }
                catch { fail(error) }
            }
            file = nil
            silence = nil
            converter = nil
        }
        if tap != 0 { report(AudioHardwareDestroyProcessTap(tap), action: "release the audio tap"); tap = 0 }
    }

    // MARK: Devices

    private var routeSelectors: [AudioObjectPropertySelector] {
        source == .system ? [kAudioHardwarePropertyDefaultOutputDevice] : [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices]
    }
    private func makeTap() throws {
        let description = CATapDescription(monoGlobalTapButExcludeProcesses: ownAudioProcess())
        description.uuid = UUID()
        description.name = "Ultra Transcribe meeting audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        if #available(macOS 26, *), let id = Bundle.main.bundleIdentifier { description.bundleIDs = [id] }
        try check(AudioHardwareCreateProcessTap(description, &tap), action: "create the system audio tap")
        tapUID = description.uuid.uuidString
    }
    /// Connects the recorder to the current device: an aggregate of the tap clocked by the default output, or the
    /// microphone `AudioDevice.microphone` picks.
    private func open() throws {
        if source == .system {
            guard let output = AudioDevice.defaultDevice(input: false).flatMap(AudioDevice.device) else { throw AppError.message("No audio output device is available.") }
            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Ultra Transcribe Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: output.uid,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output.uid]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), action: "prepare the audio capture device")
            device = aggregate
            outputUID = output.uid
        } else {
            guard case .microphone(let preferred) = source, let microphone = AudioDevice.microphone(preferred: preferred) else {
                throw AppError.message("No microphone is connected. Connect one, or turn off You for this recording.")
            }
            guard microphone.deliversFloat else { throw AppError.message("\(microphone.name) uses an audio format Ultra Transcribe can’t record. Choose another microphone in Settings → Recording.") }
            device = microphone.id
        }
        let target = device
        queue.sync { updateRate(of: target) }
        var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.updateRate(of: target) }
        if AudioObjectAddPropertyListenerBlock(target, &rateAddress, queue, listener) == noErr { rateListener = listener }
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, target, queue) { [weak self] now, input, _, _, _ in
            self?.receive(input, at: now.pointee.mHostTime)
        }, action: source == .system ? "connect the system audio recorder" : "connect the microphone")
        if source == .system { useOnlyTheTap() }
        try check(AudioDeviceStart(target, ioProc), action: source == .system ? "start system audio recording" : "start the microphone")
    }
    private func close() {
        guard device != 0 else { return }
        if let rateListener {
            var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(device, &rateAddress, queue, rateListener)
            self.rateListener = nil
        }
        if let ioProc {
            report(AudioDeviceStop(device, ioProc), action: "stop the audio device")
            report(AudioDeviceDestroyIOProcID(device, ioProc), action: "release the recorder")
        }
        ioProc = nil
        if aggregate != 0 { report(AudioHardwareDestroyAggregateDevice(aggregate), action: "release the audio device") }
        aggregate = 0
        device = 0
        queue.sync {} // lets buffers the old device already delivered finish before the next device starts
    }
    /// Moves the recording when the hardware changes: Mac audio follows the default output, the microphone follows
    /// `AudioDevice.microphone`. The moments in between become silence on the timeline.
    private func reroute() {
        guard device != 0 else { return }
        if source == .system {
            guard let current = AudioDevice.defaultDevice(input: false).flatMap(AudioDevice.device), current.uid != outputUID else { return }
        } else {
            guard case .microphone(let preferred) = source, let wanted = AudioDevice.microphone(preferred: preferred), wanted.id != device else { return }
        }
        close()
        do { try open() } catch { queue.sync { fail(error) } }
    }
    /// The aggregate also exposes its output device's own inputs. Turning them off for this recorder keeps a
    /// headset's microphone closed, so recording Mac audio never switches it to call quality.
    private func useOnlyTheTap() {
        guard let ioProc, let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, Int(size) >= MemoryLayout<AudioHardwareIOProcStreamUsage>.size else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        let usage = raw.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw) == noErr else { return }
        let count = Int(usage.pointee.mNumberStreams)
        guard count > 1, flagsOffset + count * MemoryLayout<UInt32>.size <= Int(size) else { return }
        let flags = (raw + flagsOffset).bindMemory(to: UInt32.self, capacity: count)
        for index in 0..<count { flags[index] = index == count - 1 ? 1 : 0 } // the tap's stream comes after the device's own
        report(AudioObjectSetPropertyData(device, &address, 0, nil, size, raw), action: "limit capture to Mac audio")
    }
    private func ownAudioProcess() -> [AudioObjectID] {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != 0 ? [object] : []
    }

    // MARK: Audio, on `queue`

    private func updateRate(of target: AudioObjectID) {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
        guard let file, AudioObjectGetPropertyData(target, &rateAddress, 0, nil, &size, &rate) == noErr, rate > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        inputFormat = format
        converter = rate == Self.fileRate ? nil : AVAudioConverter(from: format, to: file.processingFormat)
    }
    /// The tap's stream is the aggregate's last buffer; a microphone's is its first. Only the first channel is kept:
    /// on multi-input interfaces the microphone is usually input 1, and averaging would halve it.
    private func receive(_ input: UnsafePointer<AudioBufferList>, at hostTime: UInt64) {
        guard !paused, let file, let format = inputFormat else { return }
        do { try pad(file, until: AVAudioTime.seconds(forHostTime: hostTime)) }
        catch { fail(error); return }
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let stream = source == .system ? buffers.last : buffers.first, let data = stream.mData, stream.mNumberChannels > 0 else { onLevel?(0); return }
        let channels = Int(stream.mNumberChannels)
        let frames = Int(stream.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        guard frames > 0, let mono = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)), let samples = mono.floatChannelData?[0] else { onLevel?(0); return }
        let interleaved = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        for index in 0..<frames {
            let value = interleaved[index * channels]
            samples[index] = value
            sum += value * value
        }
        mono.frameLength = AVAudioFrameCount(frames)
        onLevel?(sqrt(sum / Float(frames)))
        do { try file.write(from: converted(mono, to: file.processingFormat)) }
        catch { fail(error) }
    }
    private func converted(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let converter else { return buffer }
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AppError.message("Could not allocate the audio conversion buffer.") }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw failure ?? AppError.message("Audio could not be converted.") }
        return output
    }
    /// Fills real interruptions with silence so both tracks stay on one timeline. Shortfalls below `tolerance` are
    /// ordinary callback timing and are left alone: padding them cuts tiny gaps into the audio, which sounds like static.
    private func pad(_ file: AVAudioFile, until time: Double, tolerance: Double = 0.25) throws {
        guard let silence else { return }
        let target = AVAudioFramePosition(clock.elapsed(now: time) * file.processingFormat.sampleRate)
        var gap = target - file.length
        guard Double(gap) > tolerance * file.processingFormat.sampleRate else { return }
        while gap > 0 {
            silence.frameLength = AVAudioFrameCount(min(gap, AVAudioFramePosition(silence.frameCapacity)))
            try file.write(from: silence)
            gap -= AVAudioFramePosition(silence.frameLength)
        }
    }
    private func fail(_ error: Error) {
        if !reportedError { reportedError = true; storedFailure = error.localizedDescription; paused = true; onError?(error.localizedDescription) }
    }

    // MARK: Helpers

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus, action: String) throws {
        guard status != noErr else { return }
        if source == .system {
            throw AppError.message("Could not \(action) (Core Audio \(status)). Allow Ultra Transcribe in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Reopen the app after changing permission.")
        }
        throw AppError.message("Could not \(action) (Core Audio \(status)). Check the microphone in Settings → Recording, or in System Settings → Sound.")
    }
    private func report(_ status: OSStatus, action: String) {
        if status != noErr { onError?("Could not \(action) (Core Audio \(status)).") }
    }
    deinit { stop() }
}
