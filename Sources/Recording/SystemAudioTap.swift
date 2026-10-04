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
            guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000) else { throw AppError.message("Could not allocate the audio timeline buffer.") }
            silentBuffer.frameLength = silentBuffer.frameCapacity
            for buffer in UnsafeMutableAudioBufferListPointer(silentBuffer.mutableAudioBufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            silence = silentBuffer
            file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            clock = RecordingClock(started: AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime()))
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { [weak self] now, input, _, _, _ in
                guard let self, !self.paused, let file = self.file else { return }
                do { try self.pad(file, until: AVAudioTime.seconds(forHostTime: now.pointee.mHostTime)) }
                catch { self.fail(error); return }
                guard let tapped = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)).last, tapped.mNumberChannels == format.channelCount else { self.onLevel?(0); return }
                var tapList = AudioBufferList(mNumberBuffers: 1, mBuffers: tapped)
                withUnsafePointer(to: &tapList) { list in
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list, deallocator: nil), buffer.frameLength > 0 else { self.onLevel?(0); return }
                    do {
                        try file.write(from: buffer)
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
            report(AudioDeviceStop(aggregate, ioProc), action: "stop the audio device")
            if let ioProc { report(AudioDeviceDestroyIOProcID(aggregate, ioProc), action: "release the recorder") }
            ioProc = nil
            report(AudioHardwareDestroyAggregateDevice(aggregate), action: "release the audio device")
            aggregate = 0
        }
        queue.sync {
            if let file, !reportedError {
                do { try pad(file, until: AVAudioTime.seconds(forHostTime: AudioGetCurrentHostTime())) }
                catch { fail(error) }
            }
            file = nil
            silence = nil
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
    private func pad(_ file: AVAudioFile, until time: Double) throws {
        guard let silence else { return }
        let target = AVAudioFramePosition(clock.elapsed(now: time) * file.processingFormat.sampleRate)
        var gap = target - file.length
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
