import Foundation
import UserNotifications

/// Live system telemetry, sampled once per second while the app runs.
/// Properties aren't @Published: each tick sends a single objectWillChange for all of them.
@MainActor
final class SystemStats: ObservableObject {
    nonisolated static let historyLength = 60

    private(set) var cpu: Double = 0
    private(set) var cpuHistory: [Double] = []

    private(set) var memory = MemorySnapshot()
    private(set) var memoryHistory: [Double] = []
    let memoryTotal = MachineInfo.physicalMemory

    private(set) var diskTotal: Int64 = 0
    private(set) var diskFree: Int64 = 0

    private(set) var networkIn: Double = 0
    private(set) var networkOut: Double = 0
    private(set) var networkInHistory: [Double] = []
    private(set) var networkOutHistory: [Double] = []

    private(set) var battery: BatteryInfo?
    private(set) var topCPU: [ProcessSample] = []
    private(set) var topMemory: [ProcessSample] = []
    private(set) var uptime: TimeInterval = 0

    var memoryUsed: UInt64 { memory.used }
    var memoryFraction: Double { memoryTotal == 0 ? 0 : Double(memory.used) / Double(memoryTotal) }
    var diskUsed: Int64 { max(0, diskTotal - diskFree) }
    var diskUsedFraction: Double { diskTotal == 0 ? 0 : Double(diskUsed) / Double(diskTotal) }

    private let cpuSampler = CPUSampler()
    private let processSampler = ProcessSampler()
    private var lastNetwork: (received: UInt64, sent: UInt64, time: Date)?
    private var tick = 0
    private var timer: Timer?
    private var lastLowDiskAlert: Date?

    init() {
        sample()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        // .common keeps sampling while menus are being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        // One change notification per tick instead of one per property keeps redraws to 1 Hz.
        objectWillChange.send()
        tick += 1

        cpu = cpuSampler.sample()
        append(cpu, to: &cpuHistory)

        if let snapshot = MemorySampler.sample() {
            memory = snapshot
            append(memoryFraction, to: &memoryHistory)
        }

        sampleNetwork()

        if tick % 2 == 1 {
            let processes = processSampler.sample()
            topCPU = Array(processes.sorted { $0.cpu > $1.cpu }.prefix(8))
            topMemory = Array(processes.sorted { $0.memory > $1.memory }.prefix(8))
        }

        if tick % 10 == 1 {
            sampleDisk()
            battery = BatterySampler.sample()
        }

        uptime = ProcessInfo.processInfo.systemUptime
    }

    private func sampleNetwork() {
        let totals = NetworkSampler.totals()
        let now = Date()
        if let last = lastNetwork {
            let elapsed = now.timeIntervalSince(last.time)
            if elapsed > 0 {
                networkIn = totals.received >= last.received ? Double(totals.received - last.received) / elapsed : 0
                networkOut = totals.sent >= last.sent ? Double(totals.sent - last.sent) / elapsed : 0
            }
        }
        lastNetwork = (totals.received, totals.sent, now)
        append(networkIn, to: &networkInHistory)
        append(networkOut, to: &networkOutHistory)
    }

    func sampleDisk() {
        objectWillChange.send()
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return }
        diskTotal = Int64(values.volumeTotalCapacity ?? 0)
        diskFree = values.volumeAvailableCapacityForImportantUsage ?? 0
        checkLowDisk()
    }

    private func append(_ value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func checkLowDisk() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: SettingsKey.lowDiskAlerts) as? Bool ?? true
        let thresholdGB = defaults.object(forKey: SettingsKey.lowDiskThresholdGB) as? Int ?? 15
        guard enabled, diskFree > 0, diskFree < Int64(thresholdGB) * 1_000_000_000 else { return }
        if let last = lastLowDiskAlert, Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastLowDiskAlert = Date()

        let content = UNMutableNotificationContent()
        content.title = "Your startup disk is almost full"
        content.body = "Only \(Fmt.bytes(diskFree)) left. Open Luud to clean up junk."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "low-disk", content: content, trigger: nil)
        )
    }
}

enum SettingsKey {
    static let menuBarMode = "menuBarMode"
    static let lowDiskAlerts = "lowDiskAlerts"
    static let lowDiskThresholdGB = "lowDiskThresholdGB"
}
