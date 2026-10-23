import Foundation

enum SelfTests {
    static func run() -> Int32 {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { failures.append(message) } }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("s1-self-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = Data([0, 0, 255, 127, 0, 128, 0, 0])
        let wav = PCM.wav(audio)
        check(wav.count == audio.count + 44, "WAV 长度")
        check(String(data: wav.prefix(4), encoding: .ascii) == "RIFF", "WAV 文件头")
        check(PCM.rms(Data(repeating: 0, count: 640)) == 0, "静音电平")
        check(PCM.rms(audio) > 0.7 && PCM.rms(audio) < 0.71, "PCM 有符号电平")

        let previousSettings = Data(#"{"shortcut":{"keyCode":63,"flags":0,"label":"Fn"},"routeToApps":true,"outputUID":"S1BridgeAudio_UID","triggerMode":"hold"}"#.utf8)
        if let migrated = try? JSONDecoder().decode(BridgeSettings.self, from: previousSettings) {
            check(migrated.shortcut.keyCode == 63 && migrated.routeToApps, "升级保留 Fn 和联动模式")
            check(migrated.autoConnect && migrated.lastDeviceID.isEmpty, "旧设置增加自动连接默认值")
        } else { failures.append("旧设置迁移失败") }
        let id = UUID(), other = UUID()
        var policy = ReconnectPolicy()
        check(policy.beginAttempt() == nil, "首次使用不连接未知设备")
        policy.succeeded(id); policy.connectionEnded()
        check(policy.beginAttempt() == id, "掉线后只连接记住的设备")
        check(policy.beginAttempt() == nil, "已有连接请求时不得重复发起")
        check(policy.failed(retryable: true) == 1, "第一次故障退避")
        _ = policy.beginAttempt()
        check(policy.failed(retryable: true) == 2, "连续故障增加退避")
        policy.pause()
        check(policy.beginAttempt() == nil && policy.failed(retryable: true) == nil, "主动断开不能自动连回")
        policy.resume(); policy.suspended = true
        check(policy.beginAttempt() == nil, "系统休眠时不连接")
        policy.suspended = false; policy.available = false
        check(policy.beginAttempt() == nil, "蓝牙关闭时不连接")
        policy.available = true
        check(policy.beginAttempt() == id, "蓝牙恢复后恢复已记住的连接")
        _ = policy.failed(retryable: false)
        check(policy.beginAttempt() == nil, "验证拒绝后停止自动重试")
        policy.manualAttempt(); policy.succeeded(other); policy.connectionEnded()
        check(policy.beginAttempt() == other, "成功选择新设备后更新记忆")
        policy.enabled = false; policy.connectionEnded()
        check(policy.beginAttempt() == nil, "关闭自动连接开关后不重连")

        let keys = HotkeyOutput(); keys.dryRun = true
        var events: [String] = []; keys.observer = { events.append($0) }
        try? keys.begin(Shortcut(), mode: "hold"); try? keys.begin(Shortcut(), mode: "hold")
        keys.end(); keys.end()
        check(events == ["down", "up"], "重复按下/松开必须幂等")
        events = []
        try? keys.begin(Shortcut(keyCode: 63, flags: 0, label: "Fn"), mode: "toggle"); keys.end()
        check(events == ["down", "up", "down", "up"], "开关型起止各一次")

        let model = BridgeModel(directory: root)
        model.connected = true; model.handshake = true
        model.settings.routeToApps = false; model.settings.tailMilliseconds = 0
        model.handle(["event": "key", "down": true, "key": 0])
        check(model.recording, "按下开始本地录音")
        model.handle(["event": "pcm", "channel": 1, "data": audio.base64EncodedString()])
        check(model.audioFrames == 0, "忽略未选择的音频通道")
        model.handle(["event": "pcm", "channel": 0, "data": audio.base64EncodedString()])
        model.handle(["event": "key", "down": true, "key": 0])
        check(model.audioFrames == 1, "重复按下不能清空录音")
        model.handle(["event": "key", "down": false, "key": 1])
        check(model.recording, "其他按键松开不能结束当前录音")
        model.handle(["event": "key", "down": false, "key": 0])
        check(!model.recording && model.draining, "松开进入尾音阶段")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(!model.busy, "尾音结束后恢复空闲")
        check(model.lastRecording != nil, "本地录音落盘")
        if let file = model.lastRecording, let stored = try? Data(contentsOf: file) { check(stored == wav, "录音内容完整") }
        model.begin(); model.emergencyStop()
        check(!model.busy, "紧急停止不残留录音状态")
        model.handle(["event": "pcm", "channel": 0, "data": audio.base64EncodedString()])
        check(model.audioFrames == 0, "空闲时不保存设备音频")
        model.handle(["event": "key", "down": true, "key": 0]); model.emergencyStop()
        model.handle(["event": "key", "down": true, "key": 0])
        check(!model.recording, "紧急停止后不能被重复按下事件重新启动")
        model.handle(["event": "key", "down": false, "key": 0])
        model.begin(); model.handle(["event": "fatal", "message": "模拟连接中断"])
        check(!model.busy && !model.connected, "故障后必须停止录音并断开")
        model.shutdown()

        // Exercise the packaged Python worker over real pipes, without opening
        // Bluetooth or issuing a hardware command.
        let worker = ProtocolWorker()
        var workerEvents: [String] = []
        worker.onEvent = { workerEvents.append($0["event"] as? String ?? "unknown") }
        do {
            try worker.launch()
            let deadline = Date().addingTimeInterval(4)
            while !workerEvents.contains("ready") && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            check(workerEvents.contains("ready"), "App 到 Python 的实际通信")
            worker.send("start")
            let errorDeadline = Date().addingTimeInterval(1)
            while !workerEvents.contains("error") && Date() < errorDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            check(workerEvents.contains("error"), "未连接时拒绝录音")
            worker.stop()
        } catch { failures.append("协议子进程启动失败：\(error)") }
        if failures.isEmpty { print("PASS: reconnect policy and cancellation, settings migration, native lifecycle, hotkeys, PCM/WAV, fault cleanup, packaged worker IPC (no hardware)"); return 0 }
        failures.forEach { print("FAIL: \($0)") }; return 1
    }
}
