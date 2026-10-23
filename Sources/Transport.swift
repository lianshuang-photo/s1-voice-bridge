import Foundation
import CoreBluetooth

struct NearbyDevice: Identifiable { var id: UUID; var name: String; var rssi: Int }

final class BluetoothTransport: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Both profiles are present in the installed official BLE library.
    // Host TX: EAE1 / ...2B10; host RX: EAE2 / ...2B18.
    static let serviceIDs = ["EAE0", "00010203-0405-0607-0809-0A0B0C0D1910", "00010203-0405-0607-0809-0A0B0C0D1911"]
    static let characteristicIDs = Set(["EAE1", "EAE2", "00010203-0405-0607-0809-0A0B0C0D2B10", "00010203-0405-0607-0809-0A0B0C0D2B18"])
    var onStatus: ((String) -> Void)?
    var onFound: ((NearbyDevice) -> Void)?
    var onReady: (() -> Void)?
    var onData: ((Data) -> Void)?
    var onDisconnected: ((String, Bool) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private var central: CBCentralManager?
    private var devices: [UUID: CBPeripheral] = [:]
    private var current: CBPeripheral?
    private var rx: CBCharacteristic?
    private var tx: CBCharacteristic?
    private var pendingServices = 0
    private var discovered: [CBCharacteristic] = []
    private var writeQueue: [Data] = []
    private var waitingWrite = false
    private var wantsScan = false
    private var ready = false
    private var scanToken = UUID()
    private var connectionToken = UUID()
    private var pendingConnection: (id: UUID, waitForWake: Bool)?
    var showAll = false

    func scan() {
        scanToken = UUID()
        wantsScan = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { performScan() }
    }
    private func performScan() {
        guard let central, central.state == .poweredOn, wantsScan else { return }
        let token = scanToken
        for p in central.retrieveConnectedPeripherals(withServices: Self.serviceIDs.map(CBUUID.init(string:))) { found(p, name: p.name ?? "讯飞设备", rssi: 0) }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        onStatus?("正在查找 S1，请取出语音夹并唤醒；首次配对请在系统蓝牙设置中完成。")
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.current == nil, self.scanToken == token else { return }
            self.central?.stopScan(); self.wantsScan = false
            self.onStatus?("扫描已结束。未找到时请退出讯飞助手、唤醒 S1 后重新扫描。")
        }
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            startPendingConnection(); performScan(); onAvailability?(true)
        case .unauthorized:
            onStatus?("蓝牙权限未授权，请到系统设置 → 隐私与安全性 → 蓝牙开启。")
            onAvailability?(false)
        case .poweredOff:
            onStatus?("系统蓝牙已关闭；开启后会恢复自动连接。")
            onAvailability?(false)
        case .unsupported: onStatus?("当前系统不支持蓝牙低功耗连接。"); onAvailability?(false)
        case .resetting: onAvailability?(false)
        default: onStatus?("蓝牙准备中（\(central.state.rawValue)）。")
        }
    }
    private func found(_ peripheral: CBPeripheral, name: String, rssi: Int) {
        let lower = name.lowercased()
        guard showAll || lower.contains("s1") || lower.contains("ifly") || lower.contains("讯飞") else { return }
        devices[peripheral.identifier] = peripheral
        onFound?(NearbyDevice(id: peripheral.identifier, name: name, rssi: rssi))
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        found(peripheral, name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "未命名设备", rssi: RSSI.intValue)
    }
    func connect(_ id: UUID, waitForWake: Bool = false) {
        disconnect()
        pendingConnection = (id, waitForWake)
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) }
        else { startPendingConnection() }
    }
    private func startPendingConnection() {
        guard let central, central.state == .poweredOn, let request = pendingConnection, current == nil else { return }
        guard let p = devices[request.id] ?? central.retrievePeripherals(withIdentifiers: [request.id]).first else {
            pendingConnection = nil
            onDisconnected?("系统已无法找到记住的设备，请重新扫描并连接一次 S1。", false)
            return
        }
        pendingConnection = nil; wantsScan = false; scanToken = UUID(); central.stopScan()
        connectionToken = UUID(); let token = connectionToken
        current = p; p.delegate = self; central.connect(p)
        onStatus?(request.waitForWake ? "正在等待上次的 S1，麦克风唤醒后会自动连接。" : "正在连接 \(p.name ?? "S1")…")
        // CoreBluetooth keeps a known peripheral's connection request pending
        // while it sleeps; do not cancel it on a short discovery timeout.
        if request.waitForWake { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak p] in
            guard let self, let p, self.current === p, self.connectionToken == token, !self.ready else { return }
            self.disconnect(); self.onDisconnected?("连接或服务发现超时，请确认 S1 已唤醒且讯飞助手已退出。", true)
        }
    }
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard current === peripheral else { return }
        discovered = []; peripheral.discoverServices(nil)
        onStatus?("蓝牙已连接，正在识别讯飞数据通道…")
        let token = connectionToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak peripheral] in
            guard let self, let peripheral, self.current === peripheral, self.connectionToken == token, !self.ready else { return }
            self.fail("设备已连接，但服务准备超时，将重新尝试连接。")
        }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard current === peripheral else { return }
        guard error == nil, let services = peripheral.services else { fail("无法读取蓝牙服务。"); return }
        let relevant = services.filter { Self.serviceIDs.contains($0.uuid.uuidString.uppercased()) }
        guard !relevant.isEmpty else { fail("此设备未提供已知的讯飞语音服务；请选 S1 语音夹。 ", retryable: false); return }
        pendingServices = relevant.count
        for service in relevant { peripheral.discoverCharacteristics(nil, for: service) }
    }
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard current === peripheral else { return }
        guard error == nil else { fail("无法读取讯飞蓝牙特征。"); return }
        discovered += service.characteristics ?? []; pendingServices -= 1
        guard pendingServices == 0 else { return }
        let allowed = discovered.filter { Self.characteristicIDs.contains($0.uuid.uuidString.uppercased()) }
        let reads = allowed.filter { $0.properties.contains(.notify) || $0.properties.contains(.indicate) }
        let writes = allowed.filter { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) }
        // Explicit known UUID preference, then unique capability. Never probe writes
        // against arbitrary characteristics or firmware-update services.
        rx = reads.first { $0.uuid.uuidString.uppercased() == "EAE2" } ?? reads.first { $0.uuid.uuidString.uppercased().hasSuffix("2B18") }
        if let rx {
            tx = writes.first {
                $0.service === rx.service && ($0.uuid.uuidString.uppercased() == "EAE1" || $0.uuid.uuidString.uppercased().hasSuffix("2B10"))
            }
        }
        guard let rx, tx != nil else {
            let summary = allowed.map { "\($0.uuid.uuidString.suffix(4)):\($0.properties.rawValue)" }.joined(separator: ", ")
            fail("语音通道无法唯一确定（\(summary)），此固件需要补充适配。", retryable: false); return
        }
        peripheral.setNotifyValue(true, for: rx)
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, characteristic === rx else { return }
        guard error == nil, characteristic.isNotifying else { fail("订阅语音通知失败。"); return }
        ready = true; onReady?()
    }
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral, characteristic === rx, error == nil, let data = characteristic.value, !data.isEmpty else { return }
        onData?(data)
    }
    func write(_ data: Data) {
        guard ready, let p = current, let tx else { return }
        let kind: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        let maximum = max(1, p.maximumWriteValueLength(for: kind))
        for offset in stride(from: 0, to: data.count, by: maximum) { writeQueue.append(data.subdata(in: offset..<min(offset + maximum, data.count))) }
        guard writeQueue.count < 256 else { fail("蓝牙写入队列堵塞，已断开。"); return }
        flushWrites()
    }
    private func flushWrites() {
        guard ready, let p = current, let tx, !waitingWrite else { return }
        let kind: CBCharacteristicWriteType = tx.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        while !writeQueue.isEmpty {
            if kind == .withoutResponse && !p.canSendWriteWithoutResponse { return }
            let data = writeQueue.removeFirst()
            if kind == .withResponse { waitingWrite = true }
            p.writeValue(data, for: tx, type: kind)
            if kind == .withResponse { return }
        }
    }
    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) { if current === peripheral { flushWrites() } }
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard current === peripheral else { return }
        guard error == nil else { fail("蓝牙写入失败。"); return }
        waitingWrite = false; flushWrites()
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }; current = nil; onDisconnected?("无法连接 S1。", true)
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard current === peripheral else { return }; clear(); onDisconnected?("设备已断开。", true)
    }
    private func fail(_ message: String, retryable: Bool = true) { disconnect(); onDisconnected?(message, retryable) }
    private func clear() { current = nil; rx = nil; tx = nil; ready = false; writeQueue = []; waitingWrite = false; discovered = [] }
    func disconnect() {
        scanToken = UUID(); connectionToken = UUID(); pendingConnection = nil
        if let p = current { central?.cancelPeripheralConnection(p) }
        clear(); central?.stopScan(); wantsScan = false
    }
}
