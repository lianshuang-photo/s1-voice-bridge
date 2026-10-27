import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var model: BridgeModel
    @ObservedObject var headset: WiredHeadsetModel
    @State private var mode: InputSourceMode
    var onModeChange: (InputSourceMode) -> Void

    init(model: BridgeModel, headset: WiredHeadsetModel, mode: InputSourceMode = .s1,
         onModeChange: @escaping (InputSourceMode) -> Void = { _ in }) {
        self.model = model; self.headset = headset
        self._mode = State(initialValue: mode); self.onModeChange = onModeChange
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("输入设备", selection: $mode) {
                ForEach(InputSourceMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).frame(maxWidth: 360).padding(.top, 18).padding(.bottom, 8)
            if mode == .s1 { S1ContentView(model: model) }
            else { HeadsetContentView(model: headset) }
        }
        .onChange(of: mode) { onModeChange($0) }
    }
}

struct HeadsetContentView: View {
    @ObservedObject var model: WiredHeadsetModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    if let url = Bundle.main.url(forResource: "Brandmark", withExtension: "png"), let icon = NSImage(contentsOf: url) {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 68, height: 68)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("S1 Voice Bridge").font(.largeTitle.bold())
                        Text("有线耳机按键控制 · 系统麦克风直接收音").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "开发版")\n有线耳机模式")
                        .font(.caption.monospaced()).multilineTextAlignment(.trailing).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.status, systemImage: model.sessionActive ? "waveform" : (model.capturing ? "checkmark.circle.fill" : "info.circle"))
                            .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                        HStack {
                            Text(model.sessionActive ? String(format: "输入中 · %.1f 秒", model.seconds) : "等待操作").monospacedDigit()
                            Text("最近按钮：\(model.lastButton)").foregroundStyle(.secondary)
                            Spacer()
                            Button("结束本次输入") { model.stopSession() }.disabled(!model.sessionActive)
                                .keyboardShortcut(.escape, modifiers: [])
                        }.font(.callout)
                    }.padding(8)
                }
                GroupBox("1 · 耳机与权限") {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(model.headsetPresent ? "已检测到有线耳机接口" : "请插入带线控的 3.5mm 耳机", systemImage: "headphones")
                        Text("适用于当前测试的单键线控耳机。开启后，中间键由本 App 使用；同一插孔换接另一副耳机也会沿用规则。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            if model.listenGranted {
                                Label("输入监控已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("授权输入监控…") { HeadsetCapture.requestPermission(); model.retry() }
                            }
                            if model.accessibility {
                                Label("辅助功能已授权", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            } else {
                                Button("授权辅助功能…") { HotkeyOutput.requestPermission(); model.retry() }
                            }
                            Spacer()
                            Button("刷新检测") { model.retry() }
                        }.font(.callout)
                        if model.devices.count > 1 {
                            Picker("线控接口", selection: $model.selected) {
                                Text("请选择").tag(UInt64?.none)
                                ForEach(model.devices) { Text("\($0.name) · \($0.id)").tag(Optional($0.id)) }
                            }.disabled(model.capturing)
                        }
                        Divider()
                        Toggle("接管有线耳机按键", isOn: $model.settings.enabled)
                        Text("只接管这一个音频接口的线控。Siri 的其他入口、键盘、鼠标和系统音频选择保持原样；关闭接管或退出 App 后释放按键。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("2 · 耳机按键与语音输入") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("耳机按钮操作", selection: $model.settings.interaction) {
                            Text("点一下开始，再点一下结束（推荐）").tag("click")
                            Text("按住说话，松开结束").tag("hold")
                        }
                        Text("部分 3.5mm 耳机长按按钮时会压低麦克风声音。若按住时收不到声音，请使用点按开关，或让输入工具使用其他麦克风。")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Text("目标快捷键：\(model.settings.shortcut.label)")
                            Spacer()
                            if model.shortcutCapture { Button("取消录入") { model.cancelShortcut() } }
                            else { Button("录入快捷键") { model.recordShortcut() } }
                            Button("Fn") { model.settings.shortcut = Shortcut(keyCode: 63, flags: 0, label: "Fn") }
                        }
                        Picker("目标软件的快捷键方式", selection: $model.settings.triggerMode) {
                            Text("按住型（例如豆包 Fn）").tag("hold")
                            Text("开关型（开始和结束各按一次）").tag("toggle")
                        }
                        Picker("单次输入上限", selection: $model.settings.maximumSeconds) {
                            ForEach(Array(stride(from: 10, through: 300, by: 10)), id: \.self) { Text("\($0) 秒").tag($0) }
                        }.frame(maxWidth: 300)
                    }.padding(8).disabled(model.sessionActive)
                }
                GroupBox("3 · 收音设置") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("检测到的耳机麦克风：\(model.inputName)").font(.headline)
                        Text("在豆包、微信或其他语音输入工具里选择这个麦克风。有线耳机模式直接使用系统收音，不经过 S1 Bridge Audio，也不依赖讯飞助手。")
                            .font(.callout).foregroundStyle(.secondary)
                        Text("配置完成后，把光标放进目标文本框，再操作耳机按钮。本 App 只触发快捷键，不自动提交消息，也不保存有线耳机录音。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(8)
                }
                HStack {
                    Text("关闭窗口后仍在菜单栏运行。拔出耳机、电脑休眠或达到时长上限会结束本次输入。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("停止接管并恢复系统按键") { model.releaseCapture() }.disabled(!model.settings.enabled && !model.capturing)
                }
                DisclosureGroup("诊断信息") {
                    Text(model.logs.joined(separator: "\n")).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }.font(.caption)
            }.padding(24)
        }.frame(minWidth: 820, idealWidth: 900, minHeight: 740)
    }
}
