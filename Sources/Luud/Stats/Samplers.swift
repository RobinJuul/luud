import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps

private let hostPort = mach_host_self()

// MARK: - CPU

final class CPUSampler {
    private var previous: [UInt32] = []

    /// Returns total CPU usage across all cores as a fraction (0...1) since the previous call.
    func sample() -> Double {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return 0 }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let current = UnsafeBufferPointer(start: info, count: Int(infoCount)).map { UInt32(bitPattern: $0) }
        defer { previous = current }
        guard previous.count == current.count else { return 0 }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for cpu in 0..<Int(cpuCount) {
            let base = cpu * Int(CPU_STATE_MAX)
            func delta(_ state: Int32) -> UInt64 {
                UInt64(current[base + Int(state)] &- previous[base + Int(state)])
            }
            let user = delta(CPU_STATE_USER), system = delta(CPU_STATE_SYSTEM)
            let nice = delta(CPU_STATE_NICE), idle = delta(CPU_STATE_IDLE)
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return total == 0 ? 0 : Double(busy) / Double(total)
    }
}

// MARK: - Memory

struct MemorySnapshot {
    var app: UInt64 = 0
    var wired: UInt64 = 0
    var compressed: UInt64 = 0
    var cached: UInt64 = 0
    var swapUsed: UInt64 = 0
    var used: UInt64 { app + wired + compressed }
}

enum MemorySampler {
    /// Same breakdown Activity Monitor uses: Memory Used = App + Wired + Compressed.
    static func sample() -> MemorySnapshot? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)
        let page = UInt64(pageSize)

        var snapshot = MemorySnapshot()
        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        snapshot.app = (internalPages > purgeable ? internalPages - purgeable : 0) * page
        snapshot.wired = UInt64(stats.wire_count) * page
        snapshot.compressed = UInt64(stats.compressor_page_count) * page
        snapshot.cached = (UInt64(stats.external_page_count) + purgeable) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
        }
        return snapshot
    }
}

// MARK: - Network

enum NetworkSampler {
    /// Cumulative bytes in/out on physical interfaces (en*), using 64-bit counters.
    static func totals() -> (received: UInt64, sent: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, 6, nil, &length, nil, 0) == 0, length > 0 else { return (0, 0) }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, 6, &buffer, &length, nil, 0) == 0 else { return (0, 0) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let messageLength = Int(header.ifm_msglen)
                guard messageLength > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if interfaceName(UInt32(info.ifm_index)).hasPrefix("en") {
                        received &+= info.ifm_data.ifi_ibytes
                        sent &+= info.ifm_data.ifi_obytes
                    }
                }
                offset += messageLength
            }
        }
        return (received, sent)
    }

    private static func interfaceName(_ index: UInt32) -> String {
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(index, &name) != nil else { return "" }
        return String(cString: name)
    }
}

// MARK: - Processes

struct ProcessSample: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let cpu: Double        // fraction of one core
    let memory: UInt64     // resident bytes
    let isApp: Bool
}

final class ProcessSampler {
    private var previousCPUTime: [pid_t: UInt64] = [:]
    private var previousSampleTime: UInt64 = 0
    private let numer: UInt64
    private let denom: UInt64

    init() {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        numer = UInt64(timebase.numer)
        denom = UInt64(max(timebase.denom, 1))
    }

    /// Samples every process the current user may inspect (root-owned processes are not visible without privileges).
    func sample() -> [ProcessSample] {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = previousSampleTime == 0 ? 0 : Double(now - previousSampleTime)
        previousSampleTime = now

        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let found = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard found > 0 else { return [] }

        let apps = Dictionary(
            NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var currentCPUTime: [pid_t: UInt64] = [:]
        var samples: [ProcessSample] = []
        for pid in pids.prefix(Int(found)) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

            let ticks = info.pti_total_user + info.pti_total_system
            let nanoseconds = UInt64(Double(ticks) * Double(numer) / Double(denom))
            currentCPUTime[pid] = nanoseconds

            var cpu = 0.0
            if elapsed > 0, let old = previousCPUTime[pid], nanoseconds >= old {
                cpu = Double(nanoseconds - old) / elapsed
            }
            let app = apps[pid]
            samples.append(ProcessSample(
                id: pid,
                name: app?.localizedName ?? Self.name(of: pid),
                cpu: cpu,
                memory: info.pti_resident_size,
                isApp: app?.activationPolicy == .regular
            ))
        }
        previousCPUTime = currentCPUTime
        return samples
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        return name.isEmpty ? "pid \(pid)" : name
    }
}

// MARK: - Battery

struct BatteryInfo: Equatable {
    var level: Double
    var isCharging: Bool
    var onACPower: Bool
    var minutesRemaining: Int?
    var cycleCount: Int?
    var health: Double?
    var temperature: Double?
}

enum BatterySampler {
    static func sample() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            var info = BatteryInfo(
                level: Double(current) / Double(maximum),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                onACPower: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                info.minutesRemaining = minutes
            }

            let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
            if service != 0 {
                defer { IOObjectRelease(service) }
                func property(_ key: String) -> Int? {
                    IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? Int
                }
                info.cycleCount = property("CycleCount")
                if let fullCharge = property("AppleRawMaxCapacity") ?? property("NominalChargeCapacity"),
                   let design = property("DesignCapacity"), design > 0 {
                    info.health = min(1, Double(fullCharge) / Double(design))
                }
                if let temperature = property("Temperature") {
                    info.temperature = Double(temperature) / 100
                }
            }
            return info
        }
        return nil
    }
}

// MARK: - Machine info

enum MachineInfo {
    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static let model = sysctlString("hw.model") ?? "Mac"
    static let chip = sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
    static let osVersion: String = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }()
    static let coreCount = ProcessInfo.processInfo.processorCount
    static let physicalMemory = ProcessInfo.processInfo.physicalMemory
}
