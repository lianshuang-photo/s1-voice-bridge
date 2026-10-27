// Documentation-only renderer. Reuses ContentView with illustrative data and
// a temporary settings directory; it never starts BLE, recording or key output.
import AppKit
import SwiftUI

@main struct ReadmeScreenshots {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        app.appearance = NSAppearance(named: .aqua)
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("s1-docs-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let model = BridgeModel(directory: scratch)
        model.keys.dryRun = true
        let deviceID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        model.devices = [NearbyDevice(id: deviceID, name: "S1 语音夹", rssi: -48)]
        model.selected = deviceID
        model.audioDevices = [AudioDevice(id: 0, name: "S1 Bridge Audio", uid: "S1BridgeAudio_UID", inputs: 2, outputs: 2)]
        model.settings.outputUID = "S1BridgeAudio_UID"
        model.settings.routeToApps = true
        model.settings.shortcut = Shortcut(keyCode: 63, flags: 0, label: "Fn")
        model.settings.autoConnect = true
        model.settings.lastDeviceName = "S1 语音夹"
        model.settings.lastDeviceID = deviceID.uuidString
        model.accessibility = true
        model.sdkVersion = "4.4.36.4"
        model.battery = "4.16 V"
        model.connected = true
        model.handshake = true
        model.status = "已就绪。按住 S1 按钮说话，松开结束。"
        model.autoConnectStatus = "已连接；掉线或休眠后会自动重连。"
        model.logs = ["S1 已连接，设备握手成功。", "虚拟麦克风：S1 Bridge Audio", "快捷键：Fn · 按住型"]

        let headset = WiredHeadsetModel(directory: scratch.appendingPathComponent("headset"))
        let view = NSHostingView(rootView: ContentView(model: model, headset: headset)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light).id("s1"))
        let size = NSSize(width: 940, height: 1120)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "S1 Voice Bridge"
        window.contentView = view
        window.appearance = NSAppearance(named: .aqua)
        view.setFrameSize(size)

        func capture(_ name: String) throws {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                throw NSError(domain: "ReadmeScreenshots", code: 1)
            }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "ReadmeScreenshots", code: 2)
            }
            try png.write(to: output.appendingPathComponent(name))
        }
        try capture("app-overview.png")
        model.connected = false
        model.handshake = false
        model.connecting = true
        model.status = "正在等待上次的 S1，麦克风唤醒后会自动连接。"
        model.autoConnectStatus = "等待记住的 S1 唤醒并连接。"
        model.logs = ["已记住上次成功连接的 S1。", "设备暂时离线，正在等待唤醒。"]
        try capture("auto-reconnect.png")
        headset.headsetPresent = true; headset.listenGranted = true; headset.accessibility = true
        headset.capturing = true; headset.settings.enabled = true
        headset.status = "已接管：点一下开始说话，再点一下结束。"
        view.rootView = ContentView(model: model, headset: headset, mode: .headset)
            .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light).id("headset")
        window.setContentSize(NSSize(width: 940, height: 930))
        view.setFrameSize(NSSize(width: 940, height: 930))
        try capture("wired-headset.png")
        print("Saved native UI screenshots with illustrative data; no hardware actions performed.")
    }
}
