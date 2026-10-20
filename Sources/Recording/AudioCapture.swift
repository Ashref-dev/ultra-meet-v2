import AppKit
import AVFoundation
import CoreAudio

/// Records one side of a meeting, Mac audio or the microphone, through Core Audio into a 16-bit, 48 kHz mono CAF.
///
/// Both sides share one timeline: they start from the same moment, and real interruptions (a device switch, a
/// stalled device, sleep) are filled with silence. Capture follows the hardware: switching speakers or headphones,
/// or connecting a microphone, moves the recording to the new device instead of losing the rest of the meeting.
///
/// Threads: start, stop and every device change run on the main thread. The device's IO callback runs on
/// `ioQueue` and only copies samples; conversion and disk writes happen on `writer`, because Core Audio waits for
/// the callback to return and a slow disk would otherwise stall the device.
final class AudioCapture: @unchecked Sendable {
    enum Source: Equatable {
        case system
        /// The microphone chosen in Settings (a device UID) and its input channel (0-based); nil for automatic.
        case microphone(preferred: String?, channel: Int?)
    }
    static let fileRate: Double = 48000
    let source: Source
    var onError: ((String) -> Void)?
    var captureFailure: String? { writer.sync { storedFailure } }
    /// The latest input level (RMS), or 0 when the device has not delivered audio for half a second.
    var level: Float {
        ioQueue.sync { AudioGetCurrentHostTime() &- lastCallback < AudioConvertNanosToHostTime(500_000_000) ? latestLevel : 0 }
    }

    private let ioQueue = DispatchQueue(label: "tn.achraf.ultratranscribe.capture.io", qos: .userInteractive)
    private let writer = DispatchQueue(label: "tn.achraf.ultratranscribe.capture.writer", qos: .userInitiated)
    // Main thread only.
    private var tap: AudioObjectID = 0
    private var tapUID = ""
    private var device: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var outputUID: String?
    /// Mac audio is first captured by an aggregate holding only the tap, so no physical device (and no headset
    /// microphone) is part of the recording. If that delivers nothing, the aggregate is clocked by the output device.
    private var clockedByOutput = false
    private var ioProc: AudioDeviceIOProcID?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var watchdog: Timer?
    private var wake: NSObjectProtocol?
    private var opened: UInt64 = 0
    private var mainPaused = false
    // `ioQueue` only.
    private var deviceRate: Double = 0
    private var channel = 0
    private var fromLastBuffer = false
    private var latestLevel: Float = 0
    private var lastCallback: UInt64 = 0
    // `writer` only.
    private var file: AVAudioFile?
    private var silence: AVAudioPCMBuffer?
    private var paused = false
    private var reportedError = false
    private var storedFailure: String?
    private var clock = RecordingClock()
    private var converter: AVAudioConverter?
    private var converterRate: Double = 0

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
            writer.sync {
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
            wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reopen()
            }
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkHealth() }
            RunLoop.main.add(timer, forMode: .common)
            watchdog = timer
        } catch { stop(); throw error }
    }
    func setPaused(_ value: Bool) {
        mainPaused = value
        writer.sync {
            let now = AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())
            if value { clock.pause(now: now) } else { clock.resume(now: now) }
            paused = value
        }
    }
    func stop() {
        watchdog?.invalidate()
        watchdog = nil
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        wake = nil
        if let routeListener {
            for selector in routeSelectors {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, routeListener)
            }
            self.routeListener = nil
        }
        close()
        writer.sync {
            if let file, !reportedError {
                do {
                    try drain(into: file)
                    try pad(file, until: AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime()), tolerance: 0)
                } catch { fail(error) }
            }
            file = nil
            silence = nil
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
    /// Connects the recorder to the current device: an aggregate of the tap, or the microphone
    /// `AudioDevice.microphone` picks.
    private func open() throws {
        dispatchPrecondition(condition: .onQueue(.main))
        var preferredChannel = 0
        if source == .system {
            var configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Ultra Transcribe Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]
            ]
            outputUID = AudioDevice.defaultDevice(input: false).flatMap(AudioDevice.device)?.uid
            if clockedByOutput {
                guard let outputUID else { throw AppError.message("No audio output device is available, so Mac audio can't be recorded.") }
                configuration[kAudioAggregateDeviceMainSubDeviceKey] = outputUID
                configuration[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: outputUID]]
            }
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), action: "prepare the audio capture device")
            device = aggregate
        } else {
            guard case .microphone(let preferred, let chosenChannel) = source, let microphone = AudioDevice.microphone(preferred: preferred) else {
                throw AppError.message("No microphone is connected. Connect one, or turn off You for this recording.")
            }
            guard microphone.deliversFloat else { throw AppError.message("\(microphone.name) uses an audio format Ultra Transcribe can’t record. Choose another microphone in Settings → Recording.") }
            device = microphone.id
            if microphone.uid == preferred, let chosenChannel, chosenChannel < microphone.channelCount { preferredChannel = chosenChannel }
        }
        let target = device
        let tapStreamIsLast = source == .system
        let rate = Self.nominalRate(of: target)
        ioQueue.sync {
            channel = preferredChannel
            fromLastBuffer = tapStreamIsLast
            deviceRate = rate
            lastCallback = 0
        }
        var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            let rate = Self.nominalRate(of: target)
            self?.ioQueue.async { self?.deviceRate = rate }
        }
        if AudioObjectAddPropertyListenerBlock(target, &rateAddress, .main, listener) == noErr { rateListener = listener }
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, target, ioQueue) { [weak self] _, input, inputTime, _, _ in
            self?.receive(input, at: inputTime.pointee)
        }, action: source == .system ? "connect the system audio recorder" : "connect the microphone")
        if source == .system && clockedByOutput { try useOnlyTheTap() }
        try check(AudioDeviceStart(target, ioProc), action: source == .system ? "start system audio recording" : "start the microphone")
        opened = AudioGetCurrentHostTime()
    }
    private func close() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard device != 0 else { return }
        if let rateListener {
            var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(device, &rateAddress, .main, rateListener)
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
        ioQueue.sync {} // the last callback has handed its samples to the writer
        writer.sync {} // and they are written before another device starts
    }
    private func reopen() {
        guard routeListener != nil else { return } // stopped
        close()
        do { try open() } catch { writer.sync { fail(error) } }
    }
    /// Moves the recording when the hardware changes: Mac audio clocked by an output device follows the default
    /// output, the microphone follows `AudioDevice.microphone`. The moments in between become silence.
    private func reroute() {
        guard device != 0 else { return reopen() }
        if source == .system {
            guard clockedByOutput, AudioDevice.defaultDevice(input: false).flatMap(AudioDevice.device)?.uid != outputUID else { return }
        } else {
            guard case .microphone(let preferred, _) = source, let wanted = AudioDevice.microphone(preferred: preferred), wanted.id != device else { return }
        }
        reopen()
    }
    /// A device that stops calling back (unplugged, a stalled driver, a tap-only aggregate that never runs) is
    /// reopened, so the rest of the meeting is still recorded.
    private func checkHealth() {
        guard !mainPaused, device != 0 else { return }
        let last = ioQueue.sync { lastCallback }
        guard AudioGetCurrentHostTime() &- max(last, opened) > AudioConvertNanosToHostTime(3_000_000_000) else { return }
        if source == .system && !clockedByOutput && last == 0 { clockedByOutput = true }
        reopen()
    }
    /// The output device's own inputs are part of an aggregate clocked by it. Turning them off for this recorder keeps
    /// a headset's microphone closed, so recording Mac audio never switches it to call quality.
    private func useOnlyTheTap() throws {
        guard let ioProc, let flagsOffset = MemoryLayout<AudioHardwareIOProcStreamUsage>.offset(of: \.mStreamIsOn) else { return }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyIOProcStreamUsage, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, Int(size) >= MemoryLayout<AudioHardwareIOProcStreamUsage>.size else { return }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioHardwareIOProcStreamUsage>.alignment)
        defer { raw.deallocate() }
        let usage = raw.bindMemory(to: AudioHardwareIOProcStreamUsage.self, capacity: 1)
        usage.pointee.mIOProc = unsafeBitCast(ioProc, to: UnsafeMutableRawPointer.self)
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, raw), action: "read the capture streams")
        let count = Int(usage.pointee.mNumberStreams)
        guard count > 1, flagsOffset + count * MemoryLayout<UInt32>.size <= Int(size) else { return }
        let flags = (raw + flagsOffset).bindMemory(to: UInt32.self, capacity: count)
        for index in 0..<count { flags[index] = index == count - 1 ? 1 : 0 } // the tap's stream comes after the device's own
        try check(AudioObjectSetPropertyData(device, &address, 0, nil, size, raw), action: "limit capture to Mac audio")
    }
    private func ownAudioProcess() -> [AudioObjectID] {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = Self.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != 0 ? [object] : []
    }
    private static func nominalRate(of device: AudioObjectID) -> Double {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
        return AudioObjectGetPropertyData(device, &rateAddress, 0, nil, &size, &rate) == noErr && rate > 0 ? rate : 0
    }

    // MARK: IO callback, on `ioQueue`

    /// Copies one channel and hands it to the writer. Nothing here waits for the disk.
    private func receive(_ input: UnsafePointer<AudioBufferList>, at time: AudioTimeStamp) {
        let host = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : AudioGetCurrentHostTime()
        lastCallback = AudioGetCurrentHostTime()
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard deviceRate > 0, let (buffer, offset) = Self.locate(channel: channel, in: buffers, fromLast: fromLastBuffer), let data = buffer.mData else {
            latestLevel = 0
            return
        }
        let stride = Int(buffer.mNumberChannels)
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride)
        guard frames > 0 else { return }
        let interleaved = data.assumingMemoryBound(to: Float.self)
        var sum: Float = 0
        let samples = [Float](unsafeUninitializedCapacity: frames) { copy, count in
            for index in 0..<frames {
                let value = interleaved[index * stride + offset]
                copy[index] = value
                sum += value * value
            }
            count = frames
        }
        latestLevel = sqrt(sum / Float(frames))
        let rate = deviceRate
        writer.async { [weak self] in self?.write(samples, rate: rate, hostTime: host) }
    }
    /// The buffer holding a channel and the channel's position in it. Mac audio's tap is the aggregate's last stream;
    /// a microphone's channels are counted across its streams, which may be interleaved or one per channel.
    static func locate(channel: Int, in buffers: UnsafeMutableAudioBufferListPointer, fromLast: Bool) -> (AudioBuffer, Int)? {
        if fromLast { return buffers.last.flatMap { $0.mNumberChannels > 0 ? ($0, 0) : nil } }
        var remaining = channel
        for buffer in buffers where buffer.mNumberChannels > 0 {
            if remaining < Int(buffer.mNumberChannels) { return (buffer, remaining) }
            remaining -= Int(buffer.mNumberChannels)
        }
        return buffers.first.flatMap { $0.mNumberChannels > 0 ? ($0, 0) : nil }
    }

    // MARK: Writing, on `writer`

    private func write(_ samples: [Float], rate: Double, hostTime: UInt64) {
        guard !paused, let file, !reportedError else { return }
        do {
            try pad(file, until: AVAudioTime.seconds(forHostTime: hostTime))
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return }
            samples.withUnsafeBufferPointer { source in
                for index in 0..<source.count { channel[index] = source[index] }
            }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            if rate == Self.fileRate {
                try drain(into: file)
                try file.write(from: buffer)
                return
            }
            if converterRate != rate || converter == nil {
                try drain(into: file)
                converter = AVAudioConverter(from: format, to: file.processingFormat)
                converterRate = rate
            }
            guard let converter else { throw AppError.message("Audio at \(Int(rate)) Hz could not be converted.") }
            try file.write(from: convert(buffer, with: converter, to: file.processingFormat, ending: false))
        } catch { fail(error) }
    }
    /// Device buffers arrive at the device's rate (44.1 kHz headphones, 16 or 24 kHz Bluetooth) and are resampled
    /// to the file's 48 kHz by one converter per rate, so its filter state carries across buffers.
    private func convert(_ buffer: AVAudioPCMBuffer?, with converter: AVAudioConverter, to format: AVAudioFormat, ending: Bool) throws -> AVAudioPCMBuffer {
        let frames = Double(buffer?.frameLength ?? 0)
        let capacity = AVAudioFrameCount((frames * format.sampleRate / converter.inputFormat.sampleRate).rounded(.up)) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw AppError.message("Could not allocate the audio conversion buffer.") }
        var supplied = buffer == nil
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, inputStatus in
            if supplied { inputStatus.pointee = ending ? .endOfStream : .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        if status == .error { throw failure ?? AppError.message("Audio could not be converted.") }
        return output
    }
    /// Writes what the converter still holds when its device goes away or the rate changes.
    private func drain(into file: AVAudioFile) throws {
        guard let converter else { return }
        self.converter = nil
        converterRate = 0
        let tail = try convert(nil, with: converter, to: file.processingFormat, ending: true)
        if tail.frameLength > 0 { try file.write(from: tail) }
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
            throw AppError.message("Could not \(action) (Core Audio \(status)). Allow Ultra Transcribe in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only, then reopen the app.")
        }
        throw AppError.message("Could not \(action) (Core Audio \(status)). Choose another microphone in Settings → Recording.")
    }
    private func report(_ status: OSStatus, action: String) {
        if status != noErr { onError?("Could not \(action) (Core Audio \(status)).") }
    }
}
