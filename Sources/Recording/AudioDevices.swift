import CoreAudio

/// Audio devices as Core Audio lists them, and the rule for which microphone records You.
struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: UInt32
    var isBluetooth: Bool { transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE }
    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    /// Virtual and combined devices (Zoom, Teams, BlackHole, aggregates) are used only when chosen or the default.
    var isVirtual: Bool { transport == kAudioDeviceTransportTypeVirtual || transport == kAudioDeviceTransportTypeAggregate || transport == kAudioDeviceTransportTypeAutoAggregate }
    /// Whether every input stream hands the recorder 32-bit float samples, Core Audio's usual format.
    var deliversFloat: Bool {
        let streams = Self.array(id, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        return !streams.isEmpty && streams.allSatisfy { stream in
            guard let format: AudioStreamBasicDescription = Self.value(stream, kAudioStreamPropertyVirtualFormat) else { return false }
            return format.mFormatID == kAudioFormatLinearPCM && format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
        }
    }
    /// Input channels across all of the device's input streams; interfaces often have several.
    var channelCount: Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let list = AudioBufferList.allocate(maximumBuffers: Int(size) / MemoryLayout<AudioBuffer>.stride + 1)
        defer { free(list.unsafeMutablePointer) }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, list.unsafeMutablePointer) == noErr else { return 0 }
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Every device with an input, in Core Audio's order.
    static func inputs() -> [AudioDevice] {
        let ids: [AudioObjectID] = array(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
        return ids.compactMap { id in
            var size = UInt32(0)
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &size) == noErr, size > 0 else { return nil }
            return device(id)
        }
    }
    static func defaultDevice(input: Bool) -> AudioObjectID? {
        let id: AudioObjectID = value(AudioObjectID(kAudioObjectSystemObject), input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        return id == 0 ? nil : id
    }
    static func device(_ id: AudioObjectID) -> AudioDevice? {
        guard let uid: String = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid, transport: value(id, kAudioDevicePropertyTransportType) ?? 0)
    }

    /// The microphone to record. A chosen device wins while it is connected. Otherwise the default input, unless it
    /// is a Bluetooth headset: opening its microphone switches it to call quality (narrow, compressed sound for
    /// everything it plays), so the built-in microphone records instead, or another wired or USB one. A headset is
    /// used only when it is the only microphone.
    static func microphone(preferred uid: String?, among inputs: [AudioDevice], defaultID: AudioObjectID?) -> AudioDevice? {
        if let uid, let chosen = inputs.first(where: { $0.uid == uid }) { return chosen }
        let standard = inputs.first { $0.id == defaultID }
        if let standard, !standard.isBluetooth { return standard }
        return inputs.first(where: \.isBuiltIn)
            ?? inputs.first { !$0.isBluetooth && !$0.isVirtual }
            ?? standard
            ?? inputs.first
    }
    static func microphone(preferred uid: String?) -> AudioDevice? {
        microphone(preferred: uid, among: inputs(), defaultID: defaultDevice(input: true))
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func value<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = address(selector)
        var size = UInt32(MemoryLayout<T>.size)
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else { return nil }
        return pointer.load(as: T.self)
    }
    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var text: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &text) == noErr, let text else { return nil }
        return text.takeRetainedValue() as String
    }
    private static func array(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }
}
