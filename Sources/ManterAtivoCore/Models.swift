import Foundation

public enum WakeMode: String, Sendable, Equatable, CaseIterable {
    case off
    case screen
    case machine

    public var title: String {
        switch self {
        case .off: "Desligada"
        case .screen: "Tela"
        case .machine: "Máquina"
        }
    }

    public var detail: String {
        switch self {
        case .off:
            "Devolve o sono na bateria. Na tomada o Mac continua sem dormir, como o desligar antigo."
        case .screen:
            "Segura a tela com caffeinate. Fechar a tampa ainda pode dormir."
        case .machine:
            "Não dorme nem com a tampa fechada. Continua valendo com o app fechado."
        }
    }
}

public enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case urgent
    case critical
    case unknown(Int)

    /// xnu `kVMPressure*`: 1 normal, 2 aviso, 4 urgente, 8 crítica.
    public static func from(sysctl value: Int) -> MemoryPressure {
        switch value {
        case 1: .normal
        case 2: .warning
        case 4: .urgent
        case 8: .critical
        default: .unknown(value)
        }
    }

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .warning: "Aviso"
        case .urgent: "Urgente"
        case .critical: "Crítica"
        case .unknown(let value): "Nível \(value)"
        }
    }

    public var isElevated: Bool {
        switch self {
        case .warning, .urgent, .critical: true
        case .normal, .unknown: false
        }
    }
}

public enum ThermalLevel: String, Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical

    public var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Morno"
        case .serious: "Quente"
        case .critical: "Crítico"
        }
    }
}

public struct CPUSample: Sendable, Equatable {
    public var totalPercent: Double?
    public var superPercent: Double?
    public var performancePercent: Double?
    public var superCoreCount: Int
    public var performanceCoreCount: Int
    public var loadAverage: Double

    public init(
        totalPercent: Double?,
        superPercent: Double?,
        performancePercent: Double?,
        superCoreCount: Int,
        performanceCoreCount: Int,
        loadAverage: Double
    ) {
        self.totalPercent = totalPercent
        self.superPercent = superPercent
        self.performancePercent = performancePercent
        self.superCoreCount = superCoreCount
        self.performanceCoreCount = performanceCoreCount
        self.loadAverage = loadAverage
    }

    public static let empty = CPUSample(
        totalPercent: nil,
        superPercent: nil,
        performancePercent: nil,
        superCoreCount: 0,
        performanceCoreCount: 0,
        loadAverage: 0
    )
}

public struct MemorySample: Sendable, Equatable {
    public var physicalBytes: UInt64
    public var freeBytes: UInt64
    public var usedBytes: UInt64
    public var compressorBytes: UInt64
    public var wiredBytes: UInt64
    public var swapUsedBytes: UInt64
    public var swapTotalBytes: UInt64
    public var swapEncrypted: Bool
    public var pressure: MemoryPressure

    public init(
        physicalBytes: UInt64,
        freeBytes: UInt64,
        usedBytes: UInt64,
        compressorBytes: UInt64,
        wiredBytes: UInt64,
        swapUsedBytes: UInt64,
        swapTotalBytes: UInt64,
        swapEncrypted: Bool,
        pressure: MemoryPressure
    ) {
        self.physicalBytes = physicalBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.compressorBytes = compressorBytes
        self.wiredBytes = wiredBytes
        self.swapUsedBytes = swapUsedBytes
        self.swapTotalBytes = swapTotalBytes
        self.swapEncrypted = swapEncrypted
        self.pressure = pressure
    }

    public static let empty = MemorySample(
        physicalBytes: 0,
        freeBytes: 0,
        usedBytes: 0,
        compressorBytes: 0,
        wiredBytes: 0,
        swapUsedBytes: 0,
        swapTotalBytes: 0,
        swapEncrypted: false,
        pressure: .unknown(0)
    )

    public var swapRatio: Double {
        guard swapTotalBytes > 0 else { return 0 }
        return Double(swapUsedBytes) / Double(swapTotalBytes)
    }
}

public struct BatterySample: Sendable, Equatable {
    public var percent: Int
    public var designmAh: Int
    public var fullmAh: Int
    public var currentmAh: Int
    public var cycleCount: Int
    public var isCharging: Bool
    public var externalConnected: Bool
    public var amperageMilliAmps: Int
    public var voltageMilliVolts: Int
    public var adapterWatts: Int?
    public var adapterName: String?
    public var systemLoadMilliWatts: Int?
    public var thermallyLimited: Bool
    public var condition: String

    public init(
        percent: Int,
        designmAh: Int,
        fullmAh: Int,
        currentmAh: Int,
        cycleCount: Int,
        isCharging: Bool,
        externalConnected: Bool,
        amperageMilliAmps: Int,
        voltageMilliVolts: Int,
        adapterWatts: Int?,
        adapterName: String?,
        systemLoadMilliWatts: Int?,
        thermallyLimited: Bool,
        condition: String
    ) {
        self.percent = percent
        self.designmAh = designmAh
        self.fullmAh = fullmAh
        self.currentmAh = currentmAh
        self.cycleCount = cycleCount
        self.isCharging = isCharging
        self.externalConnected = externalConnected
        self.amperageMilliAmps = amperageMilliAmps
        self.voltageMilliVolts = voltageMilliVolts
        self.adapterWatts = adapterWatts
        self.adapterName = adapterName
        self.systemLoadMilliWatts = systemLoadMilliWatts
        self.thermallyLimited = thermallyLimited
        self.condition = condition
    }

    public var healthRatio: Double? {
        guard designmAh > 0, fullmAh > 0 else { return nil }
        return Double(fullmAh) / Double(designmAh)
    }

    /// Carregador presente, corrente ~0, ainda não cheia, sem limite térmico.
    public var isSoftwareHold: Bool {
        externalConnected
            && !isCharging
            && abs(amperageMilliAmps) < 50
            && percent < 97
            && !thermallyLimited
    }
}

public struct ProcessRecord: Sendable, Equatable, Identifiable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var parentPid: Int32
    public var residentBytes: UInt64
    public var cpuPercent: Double
    public var path: String
    public var command: String
    public var ownedByUser: Bool

    public init(
        pid: Int32,
        parentPid: Int32,
        residentBytes: UInt64,
        cpuPercent: Double,
        path: String,
        command: String,
        ownedByUser: Bool
    ) {
        self.pid = pid
        self.parentPid = parentPid
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.path = path
        self.command = command
        self.ownedByUser = ownedByUser
    }
}

public struct AppFamily: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var residentBytes: UInt64
    public var cpuPercent: Double
    public var processCount: Int
    public var pids: [Int32]
    public var bundlePath: String?
    public var userKillable: Bool

    public init(
        id: String,
        name: String,
        residentBytes: UInt64,
        cpuPercent: Double,
        processCount: Int,
        pids: [Int32],
        bundlePath: String?,
        userKillable: Bool
    ) {
        self.id = id
        self.name = name
        self.residentBytes = residentBytes
        self.cpuPercent = cpuPercent
        self.processCount = processCount
        self.pids = pids
        self.bundlePath = bundlePath
        self.userKillable = userKillable
    }
}

public struct DuplicateSet: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var count: Int
    public var residentBytes: UInt64
    public var keepPID: Int32
    public var extraPIDs: [Int32]

    public init(
        id: String,
        title: String,
        count: Int,
        residentBytes: UInt64,
        keepPID: Int32,
        extraPIDs: [Int32]
    ) {
        self.id = id
        self.title = title
        self.count = count
        self.residentBytes = residentBytes
        self.keepPID = keepPID
        self.extraPIDs = extraPIDs
    }
}

public struct SleepHolder: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String

    public init(id: String, title: String, detail: String) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct PowerFlags: Sendable, Equatable {
    public var sleepDisabled: Bool
    public var wakeOnLAN: Bool
    public var powermode: Int?

    public init(sleepDisabled: Bool, wakeOnLAN: Bool, powermode: Int?) {
        self.sleepDisabled = sleepDisabled
        self.wakeOnLAN = wakeOnLAN
        self.powermode = powermode
    }

    public static let unknown = PowerFlags(sleepDisabled: false, wakeOnLAN: false, powermode: nil)
}

public struct WakeObservation: Sendable, Equatable {
    public var mode: WakeMode
    public var agentLoaded: Bool
    public var helperInstalled: Bool
    public var flags: PowerFlags

    public init(mode: WakeMode, agentLoaded: Bool, helperInstalled: Bool, flags: PowerFlags) {
        self.mode = mode
        self.agentLoaded = agentLoaded
        self.helperInstalled = helperInstalled
        self.flags = flags
    }

    public static let unknown = WakeObservation(
        mode: .off,
        agentLoaded: false,
        helperInstalled: false,
        flags: .unknown
    )
}

public struct DisplayInfo: Sendable, Equatable, Identifiable {
    public var id: UInt32
    public var name: String
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var pointWidth: Int
    public var pointHeight: Int
    public var refreshHz: Double
    public var isBuiltin: Bool
    public var isMain: Bool

    public init(
        id: UInt32,
        name: String,
        pixelWidth: Int,
        pixelHeight: Int,
        pointWidth: Int,
        pointHeight: Int,
        refreshHz: Double,
        isBuiltin: Bool,
        isMain: Bool
    ) {
        self.id = id
        self.name = name
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refreshHz = refreshHz
        self.isBuiltin = isBuiltin
        self.isMain = isMain
    }
}

public struct USBDeviceInfo: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ReclaimItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var bytes: UInt64
    public var exists: Bool

    public init(id: String, title: String, detail: String, bytes: UInt64, exists: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.bytes = bytes
        self.exists = exists
    }
}

public struct HistoryPoint: Codable, Sendable, Equatable {
    public var t: TimeInterval
    public var cpu: Double
    public var swap: Double
    public var memUsed: Double
    public var batt: Int?

    public init(t: TimeInterval, cpu: Double, swap: Double, memUsed: Double, batt: Int?) {
        self.t = t
        self.cpu = cpu
        self.swap = swap
        self.memUsed = memUsed
        self.batt = batt
    }
}

public enum DeskProfile: String, Sendable, Equatable {
    case mesa
    case bolso

    public var title: String {
        switch self {
        case .mesa: "Mesa"
        case .bolso: "Bolso"
        }
    }
}

public enum EnergyChoice: String, Sendable, Equatable {
    case automatic
    case low
    case high

    public var title: String {
        switch self {
        case .automatic: "Automático"
        case .low: "Baixa energia"
        case .high: "Alta potência"
        }
    }

    /// Fixed argv. Nothing here comes from the user.
    public var pmsetArguments: [String] {
        switch self {
        case .automatic:
            ["-a", "lowpowermode", "0"]
        case .low:
            ["-a", "lowpowermode", "1"]
        case .high:
            ["-a", "highpowermode", "1"]
        }
    }
}
