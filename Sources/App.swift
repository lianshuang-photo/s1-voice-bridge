import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: BridgeModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if let url = Bundle.main.url(forResource: "Brandmark", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 68, height: 68)
                    } else { Image(systemName: "mic.circle.fill").font(.system(size: 42)).foregroundStyle(.orange) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("S1 Voice Bridge").font(.largeTitle.bold())
                        Text("按住说话 · 松开结束 · 使用讯飞 S1 收音").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v0.2.2\n蓝牙自动连接").font(.caption.monospaced()).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.status, systemImage: model.recording ? "waveform" : (model.handshake ? "checkmark.circle.fill" : "info.circle"))
                            .font(.headline).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 20) {
                            Text("协议：\(model.sdkVersion)")
                            Text("电池：\(model.battery)")
                            Text("数据包：\(model.receivedPackets)")
                            Text("音频帧：\(model.audioFrames)")
                        }.font(.caption).foregroundStyle(.secondary)
                        ProgressView(value: min(1, model.inputLevel * 6)).tint(.orange)
                        HStack {
                            Text(String(format: "%.1f 秒", model.seconds)).monospacedDigit()
                            Text("最近按钮：\(model.lastKey)").foregroundStyle(.secondary)
                            Spacer()
                            Button("紧急停止") { model.emergencyStop() }.keyboardShortcut(.escape, modifiers: [])
                        }.font(.caption)
                    }.padding(8)
                }
                GroupBox("1 · 连接语音夹") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("先退出讯飞语音助手，取出并唤醒小麦克风。请选择 S1；键盘本体 T8 是另一个设备。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("扫描 S1") { model.scan() }.disabled(model.busy || model.connecting || model.connected)
                            Picker("设备", selection: $model.selected) {
                                Text("请选择").tag(UUID?.none)
                                ForEach(model.devices) { device in Text("\(device.name)  \(device.rssi == 0 ? "已配对连接" : "\(device.rssi) dBm")").tag(Optional(device.id)) }
                            }.frame(maxWidth: .infinity)
                            Button("连接") { model.connect() }.disabled(model.selected == nil || model.busy || model.connecting || model.connected)
                            Button("断开") { model.disconnect() }.disabled(!model.connected && !model.connecting)
                        }
                        Toggle("扫描时显示全部附近设备", isOn: $model.showAll).font(.caption)
                        Divider()
                        HStack {
                            Toggle("自动连接上次的 S1", isOn: $model.settings.autoConnect)
                            Spacer()
                            Button("立即重连") { model.resumeAutoConnection() }
                                .disabled(model.settings.lastDeviceID.isEmpty || model.connected || model.busy)
                        }
                        Text(model.autoConnectStatus).font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("2 · 收音与目标软件") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("启用虚拟麦克风与快捷键联动", isOn: $model.settings.routeToApps)
                        Text(model.settings.routeToApps ? "在目标 App 中选择同一个虚拟麦克风，并设置相同快捷键。说话前把光标放进目标输入框。" : "当前为本地测试：按住 S1 收音，松开后保存 WAV；不会向其他 App 发快捷键。")
                            .font(.callout).foregroundStyle(.secondary)
                        if model.settings.routeToApps {
                            HStack {
                                Picker("虚拟音频输出", selection: $model.settings.outputUID) {
                                    Text("请选择").tag("")
                                    ForEach(model.loopbacks) { device in Text(device.name).tag(device.uid) }
                                }
                                Button("刷新") { model.refreshAudio() }
                                Button("安装音频组件…") { model.installAudio() }
                            }
                            if model.loopbacks.isEmpty { Text("尚未发现虚拟麦克风。附带的安装包需要一次 macOS 管理员授权。安装后若未出现，重启后再测试。 ").font(.caption).foregroundStyle(.orange) }
                            HStack {
                                Text("快捷键：\(model.settings.shortcut.label)").frame(maxWidth: .infinity, alignment: .leading)
                                if model.shortcutCapture { Button("取消录入") { model.cancelShortcut() } }
                                else { Button("录入快捷键") { model.recordShortcut() } }
                                Button("Fn") { model.settings.shortcut = Shortcut(keyCode: 63, flags: 0, label: "Fn") }
                                if model.accessibility {
                                    Label("辅助功能已授权", systemImage: "checkmark.circle.fill")
                                        .font(.caption).foregroundStyle(.green)
                                } else {
                                    Button("授权辅助功能…") { HotkeyOutput.requestPermission(); model.refreshAccessibility() }
                                }
                            }
                            if model.shortcutCapture { Text("现在按目标快捷键；Esc 取消。 ").foregroundStyle(.orange) }
                            Picker("目标快捷键的操作方式", selection: $model.settings.triggerMode) {
                                Text("按住型：按下开始，松开结束").tag("hold")
                                Text("开关型：开始和结束各按一次").tag("toggle")
                            }
                            Text("默认 Control + Shift + D 只是示例。请以你当前 Codex、微信或豆包的设置为准；如 Fn 不响应，换成普通组合键。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Toggle("保存本地测试录音", isOn: $model.settings.saveWav)
                            Spacer()
                            Picker("音频通道", selection: $model.settings.channel) { Text("0（默认）").tag(0); Text("1").tag(1) }.frame(width: 140)
                        }
                        HStack {
                            Picker("最长录音", selection: $model.settings.maximumSeconds) {
                                ForEach(Array(stride(from: 10, through: 300, by: 10)), id: \.self) { Text("\($0) 秒").tag($0) }
                            }
                            Picker("保留尾音", selection: $model.settings.tailMilliseconds) {
                                ForEach(Array(stride(from: 0, through: 800, by: 20)), id: \.self) { Text("\($0) ms").tag($0) }
                            }
                        }.font(.caption)
                    }.padding(8).disabled(model.busy)
                }
                GroupBox("3 · 验证与诊断") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button(model.recording ? "结束测试录音" : "开始测试录音") { model.recording ? model.end() : model.begin() }.disabled(!model.handshake || model.draining)
                            Button("播放上次录音") { model.playLast() }.disabled(model.lastRecording == nil || model.busy)
                            Button("打开录音目录") { model.openRecordings() }
                            Spacer()
                            Button("导出诊断") { model.exportDiagnostics() }
                        }
                        Text("通过标准：出现按下/松开事件 → 音量条变化 → WAV 能听到 S1 收音 → 目标 App 收到文字。只显示“已连接”不算完成。")
                            .font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(model.logs.suffix(35).joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 150).padding(8).background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.padding(8)
                }
                Text("关闭窗口后仍在菜单栏运行。录音保存在本机；开启联动后，由目标 App 按它的设置处理声音。本应用不主动切换系统默认输入/输出。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }.frame(minWidth: 820, idealWidth: 900, minHeight: 740)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    let model = BridgeModel()
    private var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var connectionItem: NSMenuItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 900), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "S1 Voice Bridge"
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model))
        window.center(); window.makeKeyAndOrderFront(nil); self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        let menu = NSMenu(title: "Main Menu")
        let item = NSMenuItem(title: "S1 Voice Bridge", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "S1 Voice Bridge")
        submenu.addItem(withTitle: "退出 S1 Voice Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = submenu; menu.addItem(item); NSApplication.shared.mainMenu = menu
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "S1 Voice Bridge")
        statusItem.button?.toolTip = "S1 Voice Bridge"
        let statusMenu = NSMenu(title: "S1 Voice Bridge"); statusMenu.delegate = self
        let show = NSMenuItem(title: "显示 S1 Voice Bridge", action: #selector(showWindow), keyEquivalent: ""); show.target = self
        statusMenu.addItem(show)
        let connection = NSMenuItem(title: "立即重连", action: #selector(connectionAction), keyEquivalent: ""); connection.target = self
        statusMenu.addItem(connection); connectionItem = connection
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = statusMenu; self.statusItem = statusItem
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.model.systemWillSleep() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.model.systemDidWake() }
        model.startAutoConnection()
    }
    @objc private func showWindow() { window?.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true) }
    func applicationDidBecomeActive(_ notification: Notification) { model.refreshAccessibility() }
    @objc private func connectionAction() {
        if model.connected || model.connecting { model.disconnect() }
        else if model.settings.lastDeviceID.isEmpty { showWindow() }
        else { model.resumeAutoConnection() }
    }
    func menuWillOpen(_ menu: NSMenu) { connectionItem?.title = model.connected || model.connecting ? "断开并暂停自动连接" : "立即重连" }
    func windowShouldClose(_ sender: NSWindow) -> Bool { sender.orderOut(nil); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main struct Main {
    static func main() {
        if CommandLine.arguments.contains("--self-test") { exit(SelfTests.run()) }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate(); app.delegate = delegate; app.run()
        withExtendedLifetime(delegate) {}
    }
}
