import Foundation
import AppKit
import AVFoundation

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

struct BridgeSettings: Codable {
    var shortcut = Shortcut()
    var triggerMode = "hold"
    var routeToApps = false
    var saveWav = true
    var outputUID = ""
    var tailMilliseconds = 180
    var maximumSeconds = 120
    var channel = 0
    var targetLabel = "自定义 / Codex"
    var autoConnect = true
    var lastDeviceID = ""
    var lastDeviceName = ""

    init() {}
    enum CodingKeys: String, CodingKey {
        case shortcut, triggerMode, routeToApps, saveWav, outputUID, tailMilliseconds
        case maximumSeconds, channel, targetLabel, autoConnect, lastDeviceID, lastDeviceName
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? shortcut
        triggerMode = try c.decodeIfPresent(String.self, forKey: .triggerMode) ?? triggerMode
        routeToApps = try c.decodeIfPresent(Bool.self, forKey: .routeToApps) ?? routeToApps
        saveWav = try c.decodeIfPresent(Bool.self, forKey: .saveWav) ?? saveWav
        outputUID = try c.decodeIfPresent(String.self, forKey: .outputUID) ?? outputUID
        tailMilliseconds = try c.decodeIfPresent(Int.self, forKey: .tailMilliseconds) ?? tailMilliseconds
        maximumSeconds = try c.decodeIfPresent(Int.self, forKey: .maximumSeconds) ?? maximumSeconds
        channel = try c.decodeIfPresent(Int.self, forKey: .channel) ?? channel
        targetLabel = try c.decodeIfPresent(String.self, forKey: .targetLabel) ?? targetLabel
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? autoConnect
        lastDeviceID = try c.decodeIfPresent(String.self, forKey: .lastDeviceID) ?? lastDeviceID
        lastDeviceName = try c.decodeIfPresent(String.self, forKey: .lastDeviceName) ?? lastDeviceName
    }
}

private final class WorkerLineBuffer {
    let queue = DispatchQueue(label: "s1.worker.read")
    var data = Data()
}

final class ProtocolWorker {
    var onEvent: (([String: Any]) -> Void)?
    var onExit: ((Int32) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var identity = UUID()
    func launch() throws {
        stop()
        guard let resources = Bundle.main.resourceURL else { throw BridgeError.message("应用资源目录缺失，请重新构建。") }
        let bundled = resources.appendingPathComponent("python/bin/python3.12").path
        let configured = (try? String(contentsOf: resources.appendingPathComponent("python-path.txt"), encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = FileManager.default.isExecutableFile(atPath: bundled) ? bundled : (configured ?? "")
        guard FileManager.default.isExecutableFile(atPath: path) else { throw BridgeError.message("Python 3.12 路径失效，请重新运行构建脚本。") }
        let p = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        var environment = ProcessInfo.processInfo.environment
        environment.removeValue(forKey: "PYTHONHOME"); environment.removeValue(forKey: "PYTHONPATH")
        environment["PYTHONNOUSERSITE"] = "1"
        p.environment = environment
        p.arguments = ["-B", resources.appendingPathComponent("backend/bridge_backend.py").path]
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        let token = UUID(); identity = token
        let reader = WorkerLineBuffer()
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            reader.queue.async { [weak self] in
                reader.data.append(data)
                if reader.data.count > 1_048_576 {
                    reader.data.removeAll()
                    DispatchQueue.main.async { guard self?.identity == token else { return }; self?.onEvent?(["event": "fatal", "message": "协议进程输出超限。 "]) }
                    return
                }
                while let range = reader.data.range(of: Data([10])) {
                    let line = reader.data.subdata(in: 0..<range.lowerBound)
                    reader.data.removeSubrange(0...range.lowerBound)
                    guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    DispatchQueue.main.async { [weak self] in guard self?.identity == token else { return }; self?.onEvent?(json) }
                }
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in if handle.availableData.isEmpty { handle.readabilityHandler = nil } }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async { guard self?.identity == token else { return }; self?.onExit?(proc.terminationStatus) }
        }
        try p.run(); process = p; input = stdin.fileHandleForWriting
    }
    func send(_ command: String, _ values: [String: Any] = [:]) {
        guard process?.isRunning == true else { return }
        var message = values; message["command"] = command
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(10)
        do { try input?.write(contentsOf: data) } catch { onEvent?(["event": "fatal", "message": "无法向协议进程写入命令。 "]) }
    }
    func stop() {
        let old = process
        send("quit"); identity = UUID(); process = nil
        try? input?.close(); input = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { if old?.isRunning == true { old?.terminate() } }
    }
    deinit { if process?.isRunning == true { process?.terminate() } }
}

final class BridgeModel: ObservableObject {
    @Published var settings = BridgeSettings() {
        didSet {
            guard settingsAreReady else { return }
            saveSettings()
            if oldValue.autoConnect != settings.autoConnect {
                if !settings.autoConnect && automaticAttempt && connecting { clearConnectionState() }
                applyAutoSettings(resume: settings.autoConnect)
            }
        }
    }
    @Published var devices: [NearbyDevice] = []
    @Published var selected: UUID?
    @Published var audioDevices: [AudioDevice] = []
    @Published var status = "准备好后，唤醒 S1 并点击扫描。"
    @Published var sdkVersion = "尚未加载"
    @Published var connected = false
    @Published var connecting = false
    @Published var handshake = false
    @Published var recording = false
    @Published var draining = false
    @Published var inputLevel: Double = 0
    @Published var seconds: Double = 0
    @Published var audioFrames = 0
    @Published var receivedPackets = 0
    @Published var lastKey = "未收到"
    @Published var battery = "—"
    @Published var logs: [String] = []
    @Published var lastRecording: URL?
    @Published var shortcutCapture = false
    @Published var accessibility = HotkeyOutput.trusted
    @Published var showAll = false
    @Published var autoConnectStatus = "首次手动连接一次 S1 后，会记住这台麦克风。"
    let transport = BluetoothTransport()
    let worker = ProtocolWorker()
    let audio = AudioRoute()
    let keys = HotkeyOutput()
    let recorder = ShortcutRecorder()
    let directory: URL
    private var recordingData = Data()
    private var activeSettings = BridgeSettings()
    private var startedAt: Date?
    private var watchdog: Timer?
    private var generation = 0
    private var sessionID = UUID()
    private var heldPhysicalKey: Int?
    private var ignoreUntilRelease = false
    private var player: AVAudioPlayer?
    private var pendingConnect: UUID?
    private var handshakeTimer: Timer?
    private var quitting = false
    private var settingsAreReady = false
    private var autoStarted = false
    private var reconnect = ReconnectPolicy()
    private var retryItem: DispatchWorkItem?
    private var retryToken = UUID()
    private var currentDeviceID: UUID?
    private var automaticAttempt = false
    var busy: Bool { recording || draining }
    var loopbacks: [AudioDevice] { audioDevices.filter(\.isLoopback) }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/S1VoiceBridgeDemo")
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("settings.json")), let saved = try? JSONDecoder().decode(BridgeSettings.self, from: data) { settings = saved }
        transport.onStatus = { [weak self] text in self?.status = text; self?.log(text) }
        transport.onFound = { [weak self] device in
            guard let self else { return }
            self.devices.removeAll { $0.id == device.id }; self.devices.append(device)
            self.devices.sort { $0.name < $1.name }
            if self.selected == nil { self.selected = device.id }
        }
        transport.onReady = { [weak self] in
            guard let self else { return }
            self.connected = true; self.status = "蓝牙通道已就绪，正在完成设备握手…"
            self.worker.send("attach", ["generation": self.generation])
            self.handshakeTimer?.invalidate()
            self.handshakeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                guard let self, !self.handshake else { return }; self.fail("设备握手超时。请退出讯飞助手，重新连接后再试。")
            }
        }
        transport.onData = { [weak self] data in
            guard let self else { return }; self.receivedPackets += 1
            self.worker.send("data", ["data": data.base64EncodedString()])
        }
        transport.onDisconnected = { [weak self] text, retryable in self?.fail(text, retryable: retryable) }
        transport.onAvailability = { [weak self] available in
            guard let self else { return }
            self.reconnect.available = available
            if available { self.scheduleAutoConnection(after: 0) }
            else {
                self.cancelRetry(); self.clearConnectionState()
                self.autoConnectStatus = "等待系统蓝牙开启或授权。"
                self.persistDiagnosticStatus()
            }
        }
        worker.onEvent = { [weak self] message in self?.handle(message) }
        worker.onExit = { [weak self] code in
            guard let self, !self.quitting else { return }; self.fail("协议进程已退出（\(code)）；请重新连接。", retryable: false)
        }
        recorder.onCapture = { [weak self] shortcut in self?.settings.shortcut = shortcut; self?.shortcutCapture = false; self?.saveSettings() }
        recorder.onCancel = { [weak self] in self?.shortcutCapture = false }
        refreshAudio()
        settingsAreReady = true
        log("S1 Voice Bridge 0.2 · 自动连接就绪。")
    }

    func log(_ text: String) {
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("\(time)  \(text)")
        if logs.count > 180 { logs.removeFirst(logs.count - 180) }
        persistDiagnosticStatus()
    }
    func persistDiagnosticStatus() {
        let summary: [String: Any] = ["status": status, "sdkVersion": sdkVersion,
            "connected": connected, "handshake": handshake, "recording": recording,
            "draining": draining, "packets": receivedPackets, "audioFrames": audioFrames,
            "lastKey": lastKey, "level": inputLevel, "seconds": seconds,
            "autoConnectStatus": autoConnectStatus, "autoConnect": settings.autoConnect,
            "accessibility": HotkeyOutput.trusted, "routeToApps": settings.routeToApps,
            "lastRecording": lastRecording?.path ?? "", "logs": Array(logs.suffix(40))]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("live-status.json"), options: .atomic)
        } catch { /* Diagnostic writes must not interrupt recording. */ }
    }
    func saveSettings() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(settings)
            try data.write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        } catch { log("设置未能保存：\(error.localizedDescription)") }
    }
    func scan() {
        guard !busy else { return }
        devices = []; selected = nil; transport.showAll = showAll; transport.scan()
    }
    func connect() {
        guard let selected, !busy else { return }
        cancelRetry(); reconnect.manualAttempt()
        beginConnection(selected, automatic: false)
    }
    private func beginConnection(_ id: UUID, automatic: Bool) {
        clearConnectionState()
        reconnect.connecting = true
        currentDeviceID = id; automaticAttempt = automatic
        generation += 1; connecting = true; receivedPackets = 0; audioFrames = 0
        pendingConnect = id; status = "检查本机讯飞协议组件…"
        autoConnectStatus = automatic ? "等待记住的 S1 唤醒并连接。" : "正在连接所选设备。"
        do { try worker.launch() } catch { fail(error.localizedDescription, retryable: false) }
    }
    func disconnect() {
        cancelRetry(); reconnect.pause(); clearConnectionState()
        status = "已断开，自动连接已暂停。"
        autoConnectStatus = "已暂停；点“立即重连”或重新打开 App 恢复。"
        log(status)
    }
    private func clearConnectionState() {
        emergencyStop()
        handshakeTimer?.invalidate(); handshakeTimer = nil
        pendingConnect = nil; transport.disconnect(); worker.stop()
        connected = false; connecting = false; handshake = false; heldPhysicalKey = nil; ignoreUntilRelease = false
        currentDeviceID = nil; automaticAttempt = false
        reconnect.connectionEnded()
    }
    func startAutoConnection() {
        autoStarted = true
        applyAutoSettings(resume: true)
    }
    func pauseForOtherInput() {
        cancelShortcut()
        autoStarted = false; cancelRetry(); reconnect.pause(); clearConnectionState()
        status = "S1 模式已暂停；切回后恢复自动连接。"
        autoConnectStatus = status
        persistDiagnosticStatus()
    }
    private func applyAutoSettings(resume: Bool) {
        cancelRetry()
        reconnect.enabled = settings.autoConnect
        reconnect.target = UUID(uuidString: settings.lastDeviceID)
        if resume { reconnect.resume() }
        if !settings.autoConnect { autoConnectStatus = "自动连接已关闭。" }
        else if reconnect.target == nil { autoConnectStatus = "首次手动连接一次 S1 后，会记住这台麦克风。" }
        else if handshake { autoConnectStatus = "已连接；掉线或休眠后会自动重连。" }
        else { scheduleAutoConnection(after: 0) }
    }
    private func cancelRetry() { retryToken = UUID(); retryItem?.cancel(); retryItem = nil }
    private func scheduleAutoConnection(after delay: TimeInterval) {
        guard autoStarted, !quitting, reconnect.canAttempt, !busy else { return }
        cancelRetry(); let token = retryToken
        autoConnectStatus = delay > 0 ? "将在 \(Int(delay)) 秒后重试连接。" : "准备自动连接上次的 S1。"
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.retryToken == token, let id = self.reconnect.beginAttempt(), !self.quitting else { return }
            self.retryItem = nil; self.beginConnection(id, automatic: true)
        }
        retryItem = item
        persistDiagnosticStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
    func resumeAutoConnection() {
        if !settings.autoConnect { settings.autoConnect = true }
        reconnect.resume(); applyAutoSettings(resume: true)
    }
    func systemWillSleep() {
        reconnect.suspended = true; cancelRetry(); clearConnectionState()
        autoConnectStatus = "电脑休眠中；唤醒后恢复自动连接。"
    }
    func systemDidWake() {
        reconnect.suspended = false
        refreshAudio(); scheduleAutoConnection(after: 1)
    }
    func refreshAudio() {
        audioDevices = AudioDevices.all()
        if settings.outputUID.isEmpty, let candidate = loopbacks.first { settings.outputUID = candidate.uid }
        refreshAccessibility()
    }
    func refreshAccessibility() {
        accessibility = HotkeyOutput.trusted
    }
    func handle(_ msg: [String: Any]) {
        if let incoming = msg["generation"] as? Int, incoming != generation { return }
        switch msg["event"] as? String {
        case "ready":
            sdkVersion = msg["version"] as? String ?? "unknown"
            log("讯飞设备协议组件已加载：\(sdkVersion)")
            if let id = pendingConnect { pendingConnect = nil; transport.connect(id, waitForWake: automaticAttempt) }
        case "write":
            if let text = msg["data"] as? String, let data = Data(base64Encoded: text) { transport.write(data) }
        case "handshake":
            guard msg["ok"] as? Bool == true else { fail("讯飞设备拒绝握手，请检查后手动重连。", retryable: false); return }
            handshakeTimer?.invalidate(); handshakeTimer = nil
            handshake = true; connecting = false; status = "已就绪。按住 S1 按钮说话，松开结束。"
            if let id = currentDeviceID {
                reconnect.succeeded(id)
                settings.lastDeviceID = id.uuidString
                settings.lastDeviceName = devices.first(where: { $0.id == id })?.name ?? settings.lastDeviceName
            }
            autoConnectStatus = settings.autoConnect ? "已连接；掉线或休眠后会自动重连。" : "自动连接已关闭。"
            log("设备握手成功，已记住本次连接的 S1。")
            worker.send("battery")
        case "authentication":
            if msg["ok"] as? Bool != true { fail("设备验证未通过，请重新连接或用原讯飞助手确认设备正常。", retryable: false) }
        case "key":
            let down = msg["down"] as? Bool ?? false, key = msg["key"] as? Int ?? -1
            lastKey = "\(down ? "按下" : "松开") · \(key)"
            log("按钮 \(key)：\(down ? "按下" : "松开")")
            if ignoreUntilRelease {
                if !down { ignoreUntilRelease = false; heldPhysicalKey = nil }
                return
            }
            if down {
                guard heldPhysicalKey == nil else { return }
                heldPhysicalKey = key; begin()
            } else if heldPhysicalKey == key {
                heldPhysicalKey = nil; end()
            }
        case "pcm":
            guard busy, (msg["channel"] as? Int ?? 0) == activeSettings.channel,
                  let text = msg["data"] as? String, let data = Data(base64Encoded: text), !data.isEmpty, data.count % 2 == 0 else { return }
            let cap = max(10, min(activeSettings.maximumSeconds, 300)) * 32000 + 64000
            guard recordingData.count + data.count <= cap else { fail("录音容量已到上限，已结束本次输入。"); return }
            recordingData.append(data); audioFrames += 1; inputLevel = PCM.rms(data)
            if audioFrames % 25 == 0 { persistDiagnosticStatus() }
            if activeSettings.routeToApps {
                do { try audio.push(data) } catch { fail(error.localizedDescription) }
            }
        case "audio_format":
            log("收到设备音频：编码 \(msg["codec"] ?? "?")，通道 \(msg["channel"] ?? "?")")
        case "unsupported_audio":
            fail("设备返回尚未适配的音频格式：\(msg["codec"] ?? "?")。已停止，不会把未知数据当作声音输出。", retryable: false)
        case "decode_error": fail("设备音频解码失败，已停止；请导出诊断记录。", retryable: false)
        case "battery":
            if let voltage = msg["value"] as? Int, (1000...4999).contains(voltage) { battery = String(format: "%.2f V", Double(voltage) / 1000) }
            else { battery = "—" }
        case "record_ack": log("收到\(msg["started"] as? Bool == true ? "开始" : "停止")录音回包。")
        case "product": log("设备型号：\(msg["name"] ?? "unknown")")
        case "device_disconnected": fail("设备报告连接已断开。")
        case "fatal", "error": fail(msg["message"] as? String ?? "协议处理失败。", retryable: false)
        default: break
        }
    }

    func begin() {
        guard handshake, connected, !busy else { return }
        player?.stop(); activeSettings = settings
        activeSettings.maximumSeconds = max(10, min(activeSettings.maximumSeconds, 300))
        activeSettings.tailMilliseconds = max(0, min(activeSettings.tailMilliseconds, 800))
        do {
            if activeSettings.routeToApps {
                refreshAudio()
                guard let device = loopbacks.first(where: { $0.uid == activeSettings.outputUID }) else { throw BridgeError.message("未找到所选虚拟麦克风。先安装音频组件或切回本地测试。") }
                try audio.start(device: device)
                try keys.begin(activeSettings.shortcut, mode: activeSettings.triggerMode)
            }
        } catch { audio.stop(); keys.end(); status = error.localizedDescription; log(status); return }
        recordingData = Data(); inputLevel = 0; audioFrames = 0; seconds = 0
        sessionID = UUID(); startedAt = Date(); recording = true; draining = false
        status = activeSettings.routeToApps ? "正在收音，并送入虚拟麦克风…" : "正在本地收音测试…"
        worker.send("start")
        saveSettings()
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let started = self.startedAt else { return }
            self.seconds = Date().timeIntervalSince(started)
            if self.seconds >= Double(self.activeSettings.maximumSeconds) { self.log("达到最长录音时间，自动结束。"); self.end() }
        }
        let token = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.sessionID == token, self.recording, self.audioFrames == 0 else { return }
            self.log("尚未收到音频：保持说话，检查设备是否被讯飞助手占用；必要时尝试通道 1。")
        }
    }
    func end() {
        guard recording, !draining else { return }
        recording = false; draining = true; watchdog?.invalidate(); watchdog = nil
        worker.send("stop"); status = "正在收取尾音…"
        let token = sessionID
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(activeSettings.tailMilliseconds) / 1000) { [weak self] in
            guard let self, self.sessionID == token, self.draining else { return }
            self.audio.drain { [weak self] in
                guard let self, self.sessionID == token, self.draining else { return }; self.finish()
            }
        }
    }
    private func finish() {
        keys.end(); audio.stop(); recording = false; draining = false; startedAt = nil; inputLevel = 0
        saveRecording()
        status = recordingData.isEmpty ? "已结束，但没有收到音频。请查看诊断记录。" : "本次完成：\(String(format: "%.1f", Double(recordingData.count) / 32000)) 秒音频。"
        log(status)
    }
    private func saveRecording() {
        guard activeSettings.saveWav, !recordingData.isEmpty else { return }
        let folder = directory.appendingPathComponent("Recordings")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let file = folder.appendingPathComponent("S1-\(stamp)-\(UUID().uuidString.prefix(6)).wav")
            try PCM.wav(recordingData).write(to: file, options: .atomic); lastRecording = file
        } catch { log("录音保存失败：\(error.localizedDescription)") }
    }
    func emergencyStop() {
        let wasBusy = busy
        ignoreUntilRelease = heldPhysicalKey != nil
        sessionID = UUID(); watchdog?.invalidate(); watchdog = nil
        if wasBusy { worker.send("stop") }
        keys.end(); audio.stop(); recording = false; draining = false; heldPhysicalKey = nil; inputLevel = 0; startedAt = nil
        if wasBusy { saveRecording(); log("已停止录音，并释放本次快捷键。") }
    }
    private func fail(_ message: String, retryable: Bool = true) {
        let shouldRetry = retryable && (automaticAttempt || currentDeviceID == reconnect.target)
        clearConnectionState()
        status = message; log(message)
        if let delay = reconnect.failed(retryable: shouldRetry) { scheduleAutoConnection(after: delay) }
        else if !shouldRetry { cancelRetry(); autoConnectStatus = "连接已暂停；排查后点“立即重连”。" }
        persistDiagnosticStatus()
    }
    func recordShortcut() { shortcutCapture = true; recorder.start() }
    func cancelShortcut() { recorder.stop(); shortcutCapture = false }
    func playLast() {
        guard !busy, let file = lastRecording else { return }
        do { player = try AVAudioPlayer(contentsOf: file); player?.play() } catch { log(error.localizedDescription) }
    }
    func openRecordings() {
        let url = directory.appendingPathComponent("Recordings")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url)
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "S1-诊断.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = "S1 Voice Bridge 0.2\n讯飞助手：\(sdkVersion)\n蓝牙包：\(receivedPackets)\nPCM 帧：\(audioFrames)\n最近按键：\(lastKey)\n自动连接：\(autoConnectStatus)\n\n" + logs.joined(separator: "\n")
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { log(error.localizedDescription) }
    }
    func installAudio() {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("S1-Bridge-Audio.pkg")
        guard let bundled, FileManager.default.fileExists(atPath: bundled.path) else { log("音频安装包不存在，请重新构建。"); return }
        NSWorkspace.shared.open(bundled)
        log("已打开系统安装器。安装后点击刷新音频设备；若仍未显示，请稍后重启 Mac。")
    }
    func shutdown() { quitting = true; autoStarted = false; cancelRetry(); saveSettings(); recorder.stop(); clearConnectionState(); player?.stop() }
}
