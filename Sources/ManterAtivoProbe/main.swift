import Foundation
import ManterAtivoCore

@main
struct Probe {
    static func main() async {
        let sampler = HostSampler()
        _ = await sampler.take()
        try? await Task.sleep(for: .milliseconds(400))
        let host = await sampler.take()
        let censusActor = ProcessCensus()
        _ = await censusActor.sample()
        try? await Task.sleep(for: .milliseconds(700))
        let census = await censusActor.sample()
        let pmset = Shell.run(executable: "/usr/bin/pmset", arguments: ["-g"])
        let flags = WakeParser.flags(from: pmset.stdout)
        let top = census.families
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(8)
            .map { family in
                "\(family.name) \(PTFormat.bytes(family.residentBytes)) \(PTFormat.percent(family.cpuPercent, digits: 1)) n=\(family.processCount) kill=\(family.userKillable)"
            }
        let dups = census.duplicates.prefix(6).map { set in
            "\(set.title) x\(set.count) \(PTFormat.bytes(set.residentBytes)) keep=\(set.keepPID) extras=\(set.extraPIDs.count)"
        }
        let lines = [
            "cpu=\(host.cpu.totalPercent.map { PTFormat.percent($0) } ?? "nil") super=\(host.cpu.superPercent.map { PTFormat.percent($0) } ?? "nil") perf=\(host.cpu.performancePercent.map { PTFormat.percent($0) } ?? "nil") load=\(PTFormat.decimal(host.cpu.loadAverage))",
            "cores super=\(host.cpu.superCoreCount) performance=\(host.cpu.performanceCoreCount)",
            "mem used=\(PTFormat.bytes(host.memory.usedBytes)) free=\(PTFormat.bytes(host.memory.freeBytes)) compressor=\(PTFormat.bytes(host.memory.compressorBytes)) pressure=\(host.memory.pressure.title)",
            "swap \(PTFormat.bytes(host.memory.swapUsedBytes))/\(PTFormat.bytes(host.memory.swapTotalBytes)) encrypted=\(host.memory.swapEncrypted)",
            "thermal=\(host.thermal.title) sleepDisabled=\(flags.sleepDisabled) womp=\(flags.wakeOnLAN)",
            batteryLine(host.battery),
            "families:",
            top.joined(separator: "\n"),
            "duplicates:",
            dups.joined(separator: "\n"),
        ]
        print(lines.joined(separator: "\n"))
    }

    private static func batteryLine(_ battery: BatterySample?) -> String {
        guard let battery else { return "battery=nil" }
        return "battery \(battery.percent)% design=\(battery.designmAh) full=\(battery.fullmAh) now=\(battery.currentmAh) cycles=\(battery.cycleCount) charging=\(battery.isCharging) hold=\(battery.isSoftwareHold) adapter=\(battery.adapterWatts ?? -1)W load=\(battery.systemLoadMilliWatts ?? -1)mW"
    }
}
