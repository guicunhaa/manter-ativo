import Foundation

public struct PhraseInput: Sendable, Equatable {
    public var memory: MemorySample
    public var topFamilyName: String?
    public var topFamilyBytes: UInt64
    public var spotlightCPU: Double?
    public var afterEffectsCacheBytes: UInt64?
    public var battery: BatterySample?
    public var displayCount: Int
    public var wake: WakeMode
    public var wakeKnown: Bool

    public init(
        memory: MemorySample,
        topFamilyName: String?,
        topFamilyBytes: UInt64,
        spotlightCPU: Double?,
        afterEffectsCacheBytes: UInt64?,
        battery: BatterySample?,
        displayCount: Int,
        wake: WakeMode,
        wakeKnown: Bool
    ) {
        self.memory = memory
        self.topFamilyName = topFamilyName
        self.topFamilyBytes = topFamilyBytes
        self.spotlightCPU = spotlightCPU
        self.afterEffectsCacheBytes = afterEffectsCacheBytes
        self.battery = battery
        self.displayCount = displayCount
        self.wake = wake
        self.wakeKnown = wakeKnown
    }
}

public enum PhraseBuilder {
    public static func make(_ input: PhraseInput) -> String {
        var clauses: [String] = []

        if input.memory.swapTotalBytes > 0, input.memory.swapRatio >= 0.75 {
            clauses.append(
                "Swap com \(PTFormat.bytes(input.memory.swapUsedBytes)) de \(PTFormat.bytes(input.memory.swapTotalBytes))."
            )
        } else if input.memory.pressure.isElevated {
            clauses.append("Memória em \(input.memory.pressure.title.lowercased()).")
        }

        if let name = input.topFamilyName, input.topFamilyBytes >= 1_200_000_000 {
            clauses.append("\(name) está com \(PTFormat.bytes(input.topFamilyBytes)).")
        }

        if let cpu = input.spotlightCPU, cpu >= 35 {
            clauses.append("O Spotlight está em \(PTFormat.percent(cpu)).")
        }

        if let cache = input.afterEffectsCacheBytes, cache >= 20 * 1024 * 1024 * 1024 {
            clauses.append("O preview do After Effects ocupa \(PTFormat.bytes(cache)).")
        }

        if let battery = input.battery, battery.isSoftwareHold {
            let watts = battery.adapterWatts.map { " de \($0) W" } ?? ""
            clauses.append("Bateria em \(battery.percent)% com o carregador\(watts) ligado e a corrente em zero.")
        }

        if input.displayCount > 3 {
            clauses.append("\(input.displayCount) telas ligadas.")
        } else if input.displayCount == 3 {
            clauses.append("Três telas ligadas.")
        } else if input.displayCount == 2 {
            clauses.append("Duas telas ligadas.")
        }

        if input.wakeKnown, clauses.count < 3 {
            clauses.append(wakeClause(input.wake))
        }

        if clauses.isEmpty {
            return "Lendo o estado do Mac…"
        }
        return clauses.prefix(4).joined(separator: " ")
    }

    private static func wakeClause(_ mode: WakeMode) -> String {
        switch mode {
        case .off: "Vigília desligada."
        case .screen: "Vigília de tela ativa."
        case .machine: "Vigília de máquina ativa."
        }
    }
}
