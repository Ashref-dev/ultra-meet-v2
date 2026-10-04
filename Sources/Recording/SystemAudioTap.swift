import AVFoundation
import CoreAudio

final class SystemAudioTap: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tn.achraf.ultratranscribe.system-audio", qos: .userInitiated)
    private var tap: AudioObjectID = 0
    private var aggregate: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private var file: AVAudioFile?
    private var paused = false
    private var reportedError = false
    private var storedFailure: String?
    var captureFailure: String? { queue.sync { storedFailure } }
    private var clock = RecordingClock()
    private var silence: AVAudioPCMBuffer?
    /// The file is always written at the tap's rate (48 kHz). Buffers arrive at the output device's rate, which can
    /// differ (44.1 kHz headphones, 16 or 24 kHz Bluetooth during a call) and can change mid-recording, so they are
    /// converted. Writing them as-is labels 44.1 kHz audio as 48 kHz: pitched up, with gaps the timeline then fills.
    private var fileFormat: AVAudioFormat?
    private var deviceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var rateListener: AudioObjectPropertyListenerBlock?
    var onError: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    func start(url: URL) throws {
        do {
            let description = CATapDescription(monoGlobalTapButExcludeProcesses: ownAudioProcess())
            description.uuid = UUID()
            description.name = "Ultra Transcribe meeting audio"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            if #available(macOS 26, *), let id = Bundle.main.bundleIdentifier { description.bundleIDs = [id] }
            try check(AudioHardwareCreateProcessTap(description, &tap), action: "create the system audio tap")

            var output: AudioObjectID = 0
            var outputSize = UInt32(MemoryLayout<AudioObjectID>.size)
            var outputAddress = address(kAudioHardwarePropertyDefaultOutputDevice)
            try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &outputAddress, 0, nil, &outputSize, &output), action: "find the default output device")
            var uid: CFString = "" as CFString
            var uidSize = UInt32(MemoryLayout<CFString>.size)
            var uidAddress = address(kAudioDevicePropertyDeviceUID)
            let uidStatus = withUnsafeMutablePointer(to: &uid) { pointer in
                AudioObjectGetPropertyData(output, &uidAddress, 0, nil, &uidSize, pointer)
            }
            try check(uidStatus, action: "read the output device")
            let outputUID = uid as String
            let configuration: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Ultra Transcribe Audio",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceMainSubDeviceKey: outputUID,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(configuration as CFDictionary, &aggregate), action: "prepare the audio capture device")
            var streamDescription = AudioStreamBasicDescription()
            var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatAddress = address(kAudioTapPropertyFormat)
            try check(AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &formatSize, &streamDescription), action: "read the capture format")
            guard let format = AVAudioFormat(streamDescription: &streamDescription) else { throw AppError.message("System audio uses an unsupported format.") }
            fileFormat = format
            updateDeviceRate()
            var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.updateDeviceRate() }
            try check(AudioObjectAddPropertyListenerBlock(aggregate, &rateAddress, queue, listener), action: "follow the output device")
            rateListener = listener
            guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000) else { throw AppError.message("Could not allocate the audio timeline buffer.") }
            silentBuffer.frameLength = silentBuffer.frameCapacity
            for buffer in UnsafeMutableAudioBufferListPointer(silentBuffer.mutableAudioBufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            silence = silentBuffer
            file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            clock = RecordingClock(started: AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime()))
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { [weak self] now, input, _, _, _ in
                guard let self, !self.paused, let file = self.file, let deviceFormat = self.deviceFormat else { return }
                do { try self.pad(file, until: AVAudioTime.seconds(forHostTime: now.pointee.mHostTime)) }
                catch { self.fail(error); return }
                guard let tapped = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).last, tapped.mNumberChannels == format.channelCount else { self.onLevel?(0); return }
                var tapList = AudioBufferList(mNumberBuffers: 1, mBuffers: tapped)
                withUnsafePointer(to: &tapList) { list in
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: deviceFormat, bufferListNoCopy: list, deallocator: nil), buffer.frameLength > 0 else { self.onLevel?(0); return }
                    do {
                        try file.write(from: self.converted(buffer, to: format))
                        if let channel = buffer.floatChannelData?[0] {
                            var sum: Float = 0
                            for index in 0..<Int(buffer.frameLength) { sum += channel[index] * channel[index] }
                            self.onLevel?(sqrt(sum / Float(buffer.frameLength)))
                        }
                    } catch {
                        self.fail(error)
                    }
                }
            }, action: "connect the system audio recorder")
            try check(AudioDeviceStart(aggregate, ioProc), action: "start system audio recording")
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
        if aggregate != 0 {
            if let rateListener {
                var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
                AudioObjectRemovePropertyListenerBlock(aggregate, &rateAddress, queue, rateListener)
                self.rateListener = nil
            }
            report(AudioDeviceStop(aggregate, ioProc), action: "stop the audio device")
            if let ioProc { report(AudioDeviceDestroyIOProcID(aggregate, ioProc), action: "release the recorder") }
            ioProc = nil
            report(AudioHardwareDestroyAggregateDevice(aggregate), action: "release the audio device")
            aggregate = 0
        }
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
    private func ownAudioProcess() -> [AudioObjectID] {
        var pid = ProcessInfo.processInfo.processIdentifier
        var object: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var property = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != 0 ? [object] : []
    }
    /// Reads the rate buffers arrive at, on `queue`, when capture starts and whenever the output device changes it.
    private func updateDeviceRate() {
        var rate = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        var rateAddress = address(kAudioDevicePropertyNominalSampleRate)
        guard let fileFormat, AudioObjectGetPropertyData(aggregate, &rateAddress, 0, nil, &size, &rate) == noErr, rate > 0,
              let format = AVAudioFormat(commonFormat: fileFormat.commonFormat, sampleRate: rate, channels: fileFormat.channelCount, interleaved: fileFormat.isInterleaved)
        else { deviceFormat = fileFormat; converter = nil; return }
        deviceFormat = format
        converter = rate == fileFormat.sampleRate ? nil : AVAudioConverter(from: format, to: fileFormat)
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
        if status == .error { throw failure ?? AppError.message("System audio could not be converted.") }
        return output
    }
    /// Fills real interruptions (a stalled or switched device) with silence so both tracks stay on one timeline.
    /// Shortfalls below `tolerance` are ordinary callback timing and are left alone: padding them cuts tiny gaps
    /// into the audio, which sounds like static.
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
    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private func check(_ status: OSStatus, action: String) throws {
        guard status == noErr else { throw AppError.message("Could not \(action) (Core Audio \(status)). Allow Ultra Transcribe in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Reopen the app after changing permission.") }
    }
    private func report(_ status: OSStatus, action: String) {
        if status != noErr { onError?("Could not \(action) (Core Audio \(status)).") }
    }
    deinit { stop() }
}
