import Foundation
import AVFoundation
import CoreAudio
import AudioToolbox

struct AudioDevice: Identifiable, Hashable {
    var id: AudioDeviceID
    var name: String
    var uid: String
    var inputs: Int
    var outputs: Int
    var isLoopback: Bool { inputs > 0 && outputs > 0 && (name.localizedCaseInsensitiveContains("S1 Bridge") || name.localizedCaseInsensitiveContains("BlackHole") || name.localizedCaseInsensitiveContains("Loopback") || name.localizedCaseInsensitiveContains("MiRemote")) }
}

enum AudioDevices {
    static func text(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return "" }
        return value?.takeUnretainedValue() as String? ?? ""
    }
    static func channels(_ id: AudioDeviceID, _ scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
    static func all() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices.map { AudioDevice(id: $0, name: text($0, kAudioObjectPropertyName), uid: text($0, kAudioDevicePropertyDeviceUID), inputs: channels($0, kAudioDevicePropertyScopeInput), outputs: channels($0, kAudioDevicePropertyScopeOutput)) }.sorted { $0.name < $1.name }
    }
}

final class AudioRoute {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var pending = 0
    private var epoch = UUID()
    var queuedBuffers: Int { pending }

    func start(device: AudioDevice) throws {
        stop()
        guard device.isLoopback else { throw BridgeError.message("请选择虚拟麦克风输出，避免把收音播放到扬声器。") }
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player)
        guard let unit = engine.outputNode.audioUnit else { throw BridgeError.message("无法创建音频输出。") }
        var deviceID = device.id
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &deviceID, UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else { throw BridgeError.message("无法选择虚拟音频设备（\(status)）。") }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        player.play()
        self.engine = engine; self.player = player
    }

    func push(_ pcm: Data) throws {
        guard let player, engine?.isRunning == true else { throw BridgeError.message("虚拟音频输出已停止。") }
        guard pcm.count % 2 == 0, pcm.count > 0 else { return }
        guard pending < 100 else { throw BridgeError.message("音频输出积压超过约两秒，已停止以防错位输入。") }
        let count = pcm.count / 2
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)), let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        pcm.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for i in 0..<count {
                let raw = UInt16(bytes[i * 2]) | UInt16(bytes[i * 2 + 1]) << 8
                samples[i] = Float(Int16(bitPattern: raw)) / 32768.0
            }
        }
        pending += 1
        let token = epoch
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async { guard let self, self.epoch == token else { return }; self.pending = max(0, self.pending - 1) }
        }
    }

    func drain(_ completion: @escaping () -> Void) {
        let token = epoch, deadline = Date().addingTimeInterval(2)
        func poll() {
            guard token == self.epoch else { completion(); return }
            if self.pending == 0 || Date() >= deadline { completion(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: poll)
        }
        poll()
    }

    func stop() {
        epoch = UUID(); player?.stop(); engine?.stop(); player = nil; engine = nil; pending = 0
    }
}

enum PCM {
    static func rms(_ bytes: Data) -> Double {
        guard bytes.count >= 2 else { return 0 }
        var sum = 0.0
        bytes.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
            for i in stride(from: 0, to: b.count - 1, by: 2) {
                let sample = Double(Int16(bitPattern: UInt16(b[i]) | UInt16(b[i+1]) << 8)) / 32768
                sum += sample * sample
            }
        }
        return sqrt(sum / Double(bytes.count / 2))
    }
    static func wav(_ pcm: Data) -> Data {
        var data = Data()
        func str(_ s: String) { data.append(contentsOf: s.utf8) }
        func u32(_ x: UInt32) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u16(_ x: UInt16) { var value = x.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(pcm.count) + 36); str("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(16000); u32(32000); u16(2); u16(16); str("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}
