import Foundation
import AppKit
import IOKit
import IOKit.hid
import CoreAudio

enum InputSourceMode: String, CaseIterable {
    case s1, headset
    var title: String { self == .s1 ? "讯飞 S1" : "有线耳机" }
}

enum HeadsetScheduling {
    static func timer(every interval: TimeInterval, _ block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

struct HeadsetSettings: Codable {
    var enabled = false
    var interaction = "click"
    var shortcut = Shortcut(keyCode: 63, flags: 0, label: "Fn")
    var triggerMode = "hold"
    var maximumSeconds = 120

    init() {}
    enum CodingKeys: String, CodingKey { case enabled, interaction, shortcut, triggerMode, maximumSeconds }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        interaction = try values.decodeIfPresent(String.self, forKey: .interaction) ?? interaction
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? shortcut
        triggerMode = try values.decodeIfPresent(String.self, forKey: .triggerMode) ?? triggerMode
        maximumSeconds = try values.decodeIfPresent(Int.self, forKey: .maximumSeconds) ?? maximumSeconds
    }
}

/// Physical-button state is separate from the shortcut's hold/toggle mode.
/// Click mode starts on release, allowing an analogue headset's mic to recover.
struct HeadsetGesture {
    enum Action: Equatable { case start, stop }
    private(set) var down = false
    private(set) var active = false
    private var ignoreUntilRelease = false

    mutating func receive(down newValue: Bool, interaction: String) -> Action? {
        guard newValue != down else { return nil }
        down = newValue
        if ignoreUntilRelease {
            if !newValue { ignoreUntilRelease = false }
            return nil
        }
        if interaction == "hold" {
            active = newValue
            return newValue ? .start : .stop
        }
        guard !newValue else { return nil }
        active.toggle()
        return active ? .start : .stop
    }
    mutating func cancel() {
        active = false
        ignoreUntilRelease = down
    }
    mutating func reset() { self = HeadsetGesture() }
}

struct HeadsetDevice: Identifiable {
    let id: UInt64
    let name: String
}

final class HeadsetCapture {
    var onEdge: ((Bool) -> Void)?
    var onRemoval: (() -> Void)?
    private var device: IOHIDDevice?
    private(set) var registryID: UInt64?

    static var permissionGranted: Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }
    static func requestPermission() {
        if !permissionGranted { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
    static func matches(product: String?, transport: String?, page: Int, usage: Int) -> Bool {
        product == "Headset" && transport == "Audio" && page == 0x0c && usage == 0x01
    }
    static func devices() -> [HeadsetDevice] {
        let matching: [String: Any] = [kIOProviderClassKey: kIOHIDDeviceKey,
            kIOPropertyMatchKey: [kIOHIDProductKey: "Headset", kIOHIDTransportKey: "Audio"]]
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching as CFDictionary, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [HeadsetDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == IO_OBJECT_NULL { break }
            defer { IOObjectRelease(service) }
            func property(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }
            guard matches(product: property(kIOHIDProductKey) as? String,
                          transport: property(kIOHIDTransportKey) as? String,
                          page: (property(kIOHIDPrimaryUsagePageKey) as? NSNumber)?.intValue ?? -1,
                          usage: (property(kIOHIDPrimaryUsageKey) as? NSNumber)?.intValue ?? -1) else { continue }
            var id: UInt64 = 0
            if IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS {
                result.append(HeadsetDevice(id: id, name: "有线耳机线控（内置音频接口）"))
            }
        }
        return result.sorted { $0.id < $1.id }
    }
    func open(_ id: UInt64) throws {
        close()
        guard Self.permissionGranted else { throw BridgeError.message("请先授予输入监控权限。") }
        guard let matching = IORegistryEntryIDMatching(id) else { throw BridgeError.message("耳机设备标识无效。") }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw BridgeError.message("耳机设备已离线，请刷新后重试。") }
        defer { IOObjectRelease(service) }
        guard let candidate = IOHIDDeviceCreate(kCFAllocatorDefault, service),
              Self.matches(product: IOHIDDeviceGetProperty(candidate, kIOHIDProductKey as CFString) as? String,
                           transport: IOHIDDeviceGetProperty(candidate, kIOHIDTransportKey as CFString) as? String,
                           page: (IOHIDDeviceGetProperty(candidate, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? -1,
                           usage: (IOHIDDeviceGetProperty(candidate, kIOHIDPrimaryUsageKey as CFString) as? NSNumber)?.intValue ?? -1) else {
            throw BridgeError.message("所选设备不是已支持的有线耳机线控。")
        }
        device = candidate
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(candidate, { context, result, _, value in
            guard let context, result == kIOReturnSuccess else { return }
            let owner = Unmanaged<HeadsetCapture>.fromOpaque(context).takeUnretainedValue()
            let element = IOHIDValueGetElement(value)
            guard let current = owner.device, IOHIDElementGetDevice(element) === current,
                  IOHIDElementGetUsagePage(element) == 0x0c,
                  IOHIDElementGetUsage(element) == 0xcd else { return }
            owner.onEdge?(IOHIDValueGetIntegerValue(value) != 0)
        }, context)
        IOHIDDeviceRegisterRemovalCallback(candidate, { context, _, _ in
            guard let context else { return }
            let owner = Unmanaged<HeadsetCapture>.fromOpaque(context).takeUnretainedValue()
            owner.close(); owner.onRemoval?()
        }, context)
        IOHIDDeviceScheduleWithRunLoop(candidate, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        guard result == kIOReturnSuccess else {
            close()
            throw BridgeError.message(String(format: "无法接管耳机按键（0x%08X）；请退出其他线控映射工具后重试。", UInt32(bitPattern: result)))
        }
        registryID = id
    }
    func close() {
        guard let previous = device else { return }
        device = nil; registryID = nil
        IOHIDDeviceRegisterInputValueCallback(previous, nil, nil)
        IOHIDDeviceRegisterRemovalCallback(previous, nil, nil)
        IOHIDDeviceClose(previous, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDDeviceUnscheduleFromRunLoop(previous, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }
    deinit { close() }
}

enum HeadsetAudio {
    private static func number(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    static func snapshot() -> (plugged: Bool, input: String) {
        let devices = AudioDevices.all()
        let builtIn = devices.filter { number($0.id, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeBuiltIn }
        // Current Apple-silicon jack devices expose these UIDs and source 'emic',
        // while JackIsConnected is not implemented on every driver.
        let external = builtIn.first { $0.inputs > 0 &&
            ($0.uid == "BuiltInHeadphoneInputDevice" || number($0.id, kAudioDevicePropertyDataSource, kAudioObjectPropertyScopeInput) == 0x656d6963) }
        let plugged = external != nil || builtIn.contains {
            $0.uid == "BuiltInHeadphoneOutputDevice" ||
            number($0.id, kAudioDevicePropertyJackIsConnected, kAudioObjectPropertyScopeOutput) == 1
        }
        return (plugged, external?.name ?? "请在目标输入工具中选择麦克风")
    }
}

final class WiredHeadsetModel: ObservableObject {
    @Published var settings: HeadsetSettings {
        didSet {
            guard initialized else { return }
            if !settings.enabled || oldValue.interaction != settings.interaction ||
                oldValue.shortcut != settings.shortcut || oldValue.triggerMode != settings.triggerMode {
                stopSession(); gesture.reset()
            }
            saveSettings()
            if activated { refresh() }
        }
    }
    @Published var status = "开启接管后，用耳机按键控制语音输入。"
    @Published var capturing = false
    @Published var sessionActive = false
    @Published var listenGranted = HeadsetCapture.permissionGranted
    @Published var accessibility = HotkeyOutput.trusted
    @Published var headsetPresent = false
    @Published var inputName = "外置麦克风"
    @Published var devices: [HeadsetDevice] = []
    @Published var selected: UInt64?
    @Published var lastButton = "尚未按下"
    @Published var seconds: Double = 0
    @Published var shortcutCapture = false
    @Published var logs: [String] = []
    let keys = HotkeyOutput()
    let recorder = ShortcutRecorder()
    let capture = HeadsetCapture()
    let directory: URL
    private var gesture = HeadsetGesture()
    private var initialized = false
    private var activated = false
    private var suspended = false
    private var timer: Timer?
    private var watchdog: Timer?
    private var startedAt: TimeInterval?
    private var nextRetry: TimeInterval = 0
    private var lastDown: TimeInterval?
    private var refreshInProgress = false
    private var lastStatusData: Data?
    private var lastDiagnosticSecond = -1
    private var buttonEvents = 0

    init(directory: URL, initialShortcut: Shortcut = Shortcut(keyCode: 63, flags: 0, label: "Fn"), initialTriggerMode: String = "hold") {
        self.directory = directory
        var defaults = HeadsetSettings()
        defaults.shortcut = initialShortcut; defaults.triggerMode = initialTriggerMode
        if let data = try? Data(contentsOf: directory.appendingPathComponent("headset-settings.json")),
           let saved = try? JSONDecoder().decode(HeadsetSettings.self, from: data) { settings = saved }
        else { settings = defaults }
        if !["click", "hold"].contains(settings.interaction) { settings.interaction = "click" }
        if !["hold", "toggle"].contains(settings.triggerMode) { settings.triggerMode = "hold" }
        capture.onEdge = { [weak self] down in self?.receiveEdge(down) }
        capture.onRemoval = { [weak self] in
            guard let self else { return }
            self.stopSession(); self.gesture.reset(); self.capturing = false
            self.status = "耳机已断开；重新插入后会恢复接管。"; self.log(self.status)
        }
        recorder.onCapture = { [weak self] shortcut in self?.settings.shortcut = shortcut; self?.shortcutCapture = false }
        recorder.onCancel = { [weak self] in self?.shortcutCapture = false }
        initialized = true
    }
    func activate() {
        activated = true; suspended = false
        timer?.invalidate()
        timer = HeadsetScheduling.timer(every: 0.5) { [weak self] _ in self?.refresh() }
        refresh()
    }
    func deactivate() {
        activated = false; timer?.invalidate(); timer = nil
        stopSession(); gesture.reset(); capture.close(); capturing = false
        recorder.stop(); shortcutCapture = false
        status = "有线耳机模式已暂停，按键已交还系统。"; persistStatus()
    }
    func systemWillSleep() { suspended = true; stopSession(); capture.close(); capturing = false; gesture.reset() }
    func systemDidWake() { suspended = false; nextRetry = 0; if activated { refresh() } }
    func retry() { nextRetry = 0; refresh() }
    func refresh() {
        guard activated, !refreshInProgress else { return }
        refreshInProgress = true
        defer { refreshInProgress = false }
        let listen = HeadsetCapture.permissionGranted, trusted = HotkeyOutput.trusted
        if listenGranted != listen { listenGranted = listen }
        if accessibility != trusted { accessibility = trusted }
        let audio = HeadsetAudio.snapshot()
        if headsetPresent != audio.plugged { headsetPresent = audio.plugged }
        if inputName != audio.input { inputName = audio.input }
        if !settings.enabled || suspended || shortcutCapture || !headsetPresent || !listenGranted || !accessibility {
            if capturing || sessionActive { stopSession(); gesture.reset(); capture.close(); capturing = false }
            let message: String
            if !settings.enabled { message = "接管已关闭，耳机按键使用系统默认功能。" }
            else if suspended { message = "电脑休眠中，已释放耳机按键。" }
            else if shortcutCapture { message = "请在键盘上录入快捷键；完成后恢复耳机接管。" }
            else if !headsetPresent { message = "等待插入有线耳机。" }
            else if !listenGranted { message = "请先授予输入监控权限，再接管耳机按键。" }
            else { message = "请先授予辅助功能权限，以触发目标输入工具。" }
            if status != message { status = message }
            persistStatus(); return
        }
        if capturing { return }
        guard ProcessInfo.processInfo.systemUptime >= nextRetry else { return }
        devices = HeadsetCapture.devices()
        if selected == nil || !devices.contains(where: { $0.id == selected }) {
            selected = devices.count == 1 ? devices.first?.id : nil
        }
        guard let selected else {
            status = devices.isEmpty ? "没有找到支持的有线耳机线控。" : "检测到多个线控接口，请选择后接管。"
            nextRetry = ProcessInfo.processInfo.systemUptime + 2; persistStatus(); return
        }
        do {
            try capture.open(selected); capturing = true; gesture.reset()
            status = settings.interaction == "click" ? "已接管：点一下开始说话，再点一下结束。" : "已接管：按住说话，松开结束。"
            log("已接管有线耳机线控，其他输入设备保持原样。")
        } catch {
            status = error.localizedDescription
            nextRetry = ProcessInfo.processInfo.systemUptime + 5
            log(status)
        }
    }
    func receiveEdge(_ down: Bool) {
        guard activated, settings.enabled, capturing, down != gesture.down else { return }
        buttonEvents += 1
        if down { lastDown = ProcessInfo.processInfo.systemUptime; lastButton = "按下" }
        else { lastButton = String(format: "松开 · %.2f 秒", ProcessInfo.processInfo.systemUptime - (lastDown ?? ProcessInfo.processInfo.systemUptime)); lastDown = nil }
        log("耳机按钮：\(lastButton)")
        guard let action = gesture.receive(down: down, interaction: settings.interaction) else { persistStatus(); return }
        if action == .start { startSession() } else { stopSession() }
        persistStatus()
    }
    private func startSession() {
        guard !sessionActive else { return }
        do {
            try keys.begin(settings.shortcut, mode: settings.triggerMode)
            sessionActive = true; seconds = 0; startedAt = ProcessInfo.processInfo.systemUptime; lastDiagnosticSecond = -1
            status = settings.interaction == "click" ? "语音输入中；再点一下耳机按键即可结束。" : "语音输入中；松开耳机按键即可结束。"
            watchdog?.invalidate()
            let limit = max(10, min(settings.maximumSeconds, 300))
            watchdog = HeadsetScheduling.timer(every: 0.1) { [weak self] _ in
                guard let self, let start = self.startedAt else { return }
                self.seconds = ProcessInfo.processInfo.systemUptime - start
                if Int(self.seconds) != self.lastDiagnosticSecond {
                    self.lastDiagnosticSecond = Int(self.seconds); self.persistStatus()
                }
                if self.seconds >= Double(limit) { self.stopSession(); self.status = "已达到时长上限，语音输入已结束。"; self.log(self.status) }
            }
            log("已触发语音输入快捷键。")
        } catch {
            gesture.cancel(); keys.end(); status = error.localizedDescription; log(status)
        }
    }
    func stopSession() {
        let wasActive = sessionActive
        watchdog?.invalidate(); watchdog = nil; startedAt = nil
        keys.end(); sessionActive = false; gesture.cancel()
        if wasActive { status = "语音输入已结束。"; log(status) }
    }
    func releaseCapture() {
        settings.enabled = false
        stopSession(); capture.close(); capturing = false; gesture.reset()
        status = "接管已关闭，耳机按键已交还系统。"; persistStatus()
    }
    func recordShortcut() { shortcutCapture = true; refresh(); recorder.start() }
    func cancelShortcut() { shortcutCapture = false; recorder.stop() }
    private func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("headset-settings.json"), options: .atomic)
        } catch { log("耳机设置保存失败：\(error.localizedDescription)") }
    }
    func log(_ message: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("\(time)  \(message)"); if logs.count > 40 { logs.removeFirst(logs.count - 40) }
        persistStatus()
    }
    private func persistStatus() {
        let values: [String: Any] = ["mode": "headset", "activated": activated, "enabled": settings.enabled,
            "capturing": capturing, "headsetPresent": headsetPresent, "sessionActive": sessionActive,
            "inputMonitoring": listenGranted, "accessibility": accessibility, "status": status,
            "interaction": settings.interaction, "shortcut": settings.shortcut.label,
            "lastButton": lastButton, "buttonEvents": buttonEvents, "seconds": seconds, "inputName": inputName, "logs": logs]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]), data != lastStatusData {
            try? data.write(to: directory.appendingPathComponent("headset-status.json"), options: .atomic)
            lastStatusData = data
        }
    }
    func shutdown() { deactivate() }
}
