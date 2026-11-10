import Darwin
import Foundation
import IOKit

public struct HostReading: Sendable {
    public var cpu: CPUSample
    public var memory: MemorySample
    public var battery: BatterySample?
    public var thermal: ThermalLevel
    public var diskFreeBytes: Int64?

    public init(
        cpu: CPUSample,
        memory: MemorySample,
        battery: BatterySample?,
        thermal: ThermalLevel,
        diskFreeBytes: Int64?
    ) {
        self.cpu = cpu
        self.memory = memory
        self.battery = battery
        self.thermal = thermal
        self.diskFreeBytes = diskFreeBytes
    }
}

public actor HostSampler {
    private var previousTotal: Tick?
    private var previousCores: [Tick] = []
    private var tickCount = 0

    public init() {}

    public func take() -> HostReading {
        let cpu = readCPU()
        let memory = readMemory()
        let battery = readBattery()
        tickCount += 1
        let disk = tickCount % 5 == 1 ? ReclaimMeasure.importantFreeBytes() : nil
        return HostReading(
            cpu: cpu,
            memory: memory,
            battery: battery,
            thermal: currentThermal(),
            diskFreeBytes: disk
        )
    }

    private func readCPU() -> CPUSample {
        let total = readTotalTicks()
        let cores = readCoreTicks()
        let superCount = sysctlInt("hw.perflevel0.physicalcpu") ?? 0
        let performanceCount = sysctlInt("hw.perflevel1.physicalcpu") ?? 0
        let load = readLoad()

        let totalPercent: Double?
        if let previousTotal, let total {
            totalPercent = percent(from: previousTotal, to: total)
        } else {
            totalPercent = nil
        }
        previousTotal = total

        var superPercent: Double?
        var performancePercent: Double?
        if !previousCores.isEmpty, cores.count == previousCores.count {
            let superTicks = zip(previousCores, cores).prefix(superCount)
            let performanceTicks = zip(previousCores, cores).dropFirst(superCount).prefix(performanceCount)
            superPercent = averagePercent(Array(superTicks))
            performancePercent = averagePercent(Array(performanceTicks))
        }
        previousCores = cores

        return CPUSample(
            totalPercent: totalPercent,
            superPercent: superPercent,
            performancePercent: performancePercent,
            superCoreCount: superCount,
            performanceCoreCount: performanceCount,
            loadAverage: load
        )
    }

    private func readMemory() -> MemorySample {
        let page = UInt64(sysctlInt("hw.pagesize") ?? 16_384)
        let physical = sysctlU64("hw.memsize") ?? 0
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, raw, &count)
            }
        }
        let free = result == KERN_SUCCESS ? (UInt64(stats.free_count) + UInt64(stats.speculative_count)) * page : 0
        let compressor = result == KERN_SUCCESS ? UInt64(stats.compressor_page_count) * page : 0
        let wired = result == KERN_SUCCESS ? UInt64(stats.wire_count) * page : 0
        let used = physical > free ? physical - free : 0
        let swap = readSwap()
        let pressureValue = sysctlInt("kern.memorystatus_vm_pressure_level") ?? -1
        return MemorySample(
            physicalBytes: physical,
            freeBytes: free,
            usedBytes: used,
            compressorBytes: compressor,
            wiredBytes: wired,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            swapEncrypted: swap.encrypted,
            pressure: MemoryPressure.from(sysctl: pressureValue)
        )
    }

    private func readBattery() -> BatterySample? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let raw = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }

        let batteryData = raw["BatteryData"] as? [String: Any] ?? [:]
        let charger = raw["ChargerData"] as? [String: Any] ?? [:]
        let adapter = raw["AdapterDetails"] as? [String: Any] ?? [:]
        let telemetry = raw["PowerTelemetryData"] as? [String: Any] ?? [:]

        let design = intValue(batteryData["DesignCapacity"])
        let full = intValue(batteryData["FullChargeCapacity"])
        let current = intValue(batteryData["AppleRawCurrentCapacity"])
        let percent: Int
        if let currentCapacity = raw["CurrentCapacity"] as? Int {
            percent = currentCapacity
        } else if full > 0 {
            percent = Int((Double(current) / Double(full) * 100).rounded())
        } else {
            percent = 0
        }

        let condition: String
        if let health = full > 0 && design > 0 ? Double(full) / Double(design) : nil {
            if health >= 0.9 { condition = "Normal" }
            else if health >= 0.8 { condition = "Atenção" }
            else { condition = "Baixa" }
        } else {
            condition = "Sem leitura"
        }

        return BatterySample(
            percent: percent,
            designmAh: design,
            fullmAh: full,
            currentmAh: current,
            cycleCount: intValue(raw["CycleCount"]),
            isCharging: boolValue(raw["IsCharging"]) || boolValue(charger["IsCharging"]),
            externalConnected: boolValue(raw["ExternalConnected"]),
            amperageMilliAmps: intValue(raw["Amperage"]),
            voltageMilliVolts: intValue(raw["Voltage"]),
            adapterWatts: adapter["Watts"].map { intValue($0) },
            adapterName: adapter["Name"] as? String,
            systemLoadMilliWatts: telemetry["SystemLoad"].map { intValue($0) },
            thermallyLimited: intValue(charger["TimeChargingThermallyLimited"]) > 0,
            condition: condition
        )
    }
}

private struct Tick: Equatable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    var busy: UInt64 { user &+ system &+ nice }
    var total: UInt64 { busy &+ idle }
}

private func percent(from previous: Tick, to current: Tick) -> Double {
    let total = current.total &- previous.total
    guard total > 0 else { return 0 }
    let busy = current.busy &- previous.busy
    return min(100, Double(busy) / Double(total) * 100)
}

private func averagePercent(_ pairs: [(Tick, Tick)]) -> Double? {
    guard !pairs.isEmpty else { return nil }
    let values = pairs.map { percent(from: $0.0, to: $0.1) }
    return values.reduce(0, +) / Double(values.count)
}

private func readTotalTicks() -> Tick? {
    var info = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { raw in
            host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, raw, &count)
        }
    }
    guard result == KERN_SUCCESS else { return nil }
    let ticks = info.cpu_ticks
    return Tick(
        user: UInt64(ticks.0),
        system: UInt64(ticks.1),
        idle: UInt64(ticks.2),
        nice: UInt64(ticks.3)
    )
}

private func readCoreTicks() -> [Tick] {
    var cpuCount: natural_t = 0
    var info: processor_info_array_t?
    var infoCount: mach_msg_type_number_t = 0
    let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
    guard result == KERN_SUCCESS, let info else { return [] }
    defer {
        let size = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: info)), size)
    }
    let states = Int(CPU_STATE_MAX)
    var ticks: [Tick] = []
    ticks.reserveCapacity(Int(cpuCount))
    for index in 0..<Int(cpuCount) {
        let base = index * states
        guard base + 3 < Int(infoCount) else { break }
        ticks.append(
            Tick(
                user: UInt64(info[base + Int(CPU_STATE_USER)]),
                system: UInt64(info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt64(info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt64(info[base + Int(CPU_STATE_NICE)])
            )
        )
    }
    return ticks
}

private struct SwapRead {
    var used: UInt64
    var total: UInt64
    var encrypted: Bool
}

private func readSwap() -> SwapRead {
    var usage = xsw_usage()
    var size = MemoryLayout<xsw_usage>.stride
    let result = withUnsafeMutablePointer(to: &usage) { pointer in
        sysctlbyname("vm.swapusage", pointer, &size, nil, 0)
    }
    guard result == 0 else { return SwapRead(used: 0, total: 0, encrypted: false) }
    return SwapRead(used: usage.xsu_used, total: usage.xsu_total, encrypted: usage.xsu_encrypted != 0)
}

private func readLoad() -> Double {
    var load = loadavg()
    var size = MemoryLayout<loadavg>.stride
    let result = withUnsafeMutablePointer(to: &load) { pointer in
        sysctlbyname("vm.loadavg", pointer, &size, nil, 0)
    }
    guard result == 0, load.fscale > 0 else { return 0 }
    return Double(load.ldavg.0) / Double(load.fscale)
}

private func currentThermal() -> ThermalLevel {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: .nominal
    case .fair: .fair
    case .serious: .serious
    case .critical: .critical
    @unknown default: .nominal
    }
}

private func sysctlInt(_ name: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.stride
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return Int(value)
}

private func sysctlU64(_ name: String) -> UInt64? {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.stride
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
    return value
}

private func intValue(_ value: Any?) -> Int {
    switch value {
    case let number as Int: number
    case let number as Int32: Int(number)
    case let number as Int64: Int(number)
    case let number as UInt: Int(number)
    case let number as UInt32: Int(number)
    case let number as UInt64: Int(number)
    case let number as NSNumber: number.intValue
    default: 0
    }
}

private func boolValue(_ value: Any?) -> Bool {
    switch value {
    case let flag as Bool: flag
    case let number as NSNumber: number.boolValue
    default: false
    }
}
