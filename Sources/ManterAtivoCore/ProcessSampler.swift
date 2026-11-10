import Darwin
import Foundation

public enum CPUScale {
    /// `pti_total_user` and `pti_total_system` are Mach absolute ticks.
    /// On this Apple Silicon the tick is 125/3 ns, so treating them as
    /// nanoseconds under-reports CPU by about 42×. Intel stays 1/1.
    public static func percent(deltaTicks: UInt64, wallNanoseconds: UInt64, numer: UInt32, denom: UInt32) -> Double {
        guard wallNanoseconds > 0, numer > 0, denom > 0 else { return 0 }
        let nanoseconds = Double(deltaTicks) * Double(numer) / Double(denom)
        let percent = nanoseconds / Double(wallNanoseconds) * 100
        guard percent.isFinite, percent > 0 else { return 0 }
        return min(percent, 1_600)
    }
}

public struct PSRow: Equatable, Sendable {
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var uid: uid_t
    public var command: String
}

public enum PSSnapshot {
    public static func parse(_ stdout: String) -> [Int32: PSRow] {
        var rows: [Int32: PSRow] = [:]
        for line in stdout.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let cpu = Double(parts[1].replacing(",", with: ".")),
                  let rssKilobytes = UInt64(parts[2]),
                  let uid = uid_t(parts[3]) else { continue }
            rows[pid] = PSRow(
                cpuPercent: cpu,
                residentBytes: rssKilobytes * 1024,
                uid: uid,
                command: parts.dropFirst(4).joined(separator: " ")
            )
        }
        return rows
    }

    static func load() -> [Int32: PSRow] {
        let result = Shell.run(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,pcpu=,rss=,uid=,comm="],
            environment: ["LC_ALL": "C"],
            timeout: 2
        )
        guard result.status == 0 else { return [:] }
        return parse(result.stdout)
    }
}

private struct TickScale: Sendable {
    var numer: UInt32
    var denom: UInt32

    static let current: TickScale = {
        var info = mach_timebase_info_data_t()
        guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0, info.numer != 0 else {
            return TickScale(numer: 1, denom: 1)
        }
        return TickScale(numer: info.numer, denom: info.denom)
    }()
}

public actor ProcessCensus {
    private var previous: [Int32: (ticks: UInt64, at: ContinuousClock.Instant)] = [:]
    private let tickScale = TickScale.current

    public init() {}

    public func sample() -> (families: [AppFamily], duplicates: [DuplicateSet]) {
        let records = self.records()
        return ProcessGrouper.group(records)
    }

    private func records() -> [ProcessRecord] {
        let pids = Self.pids()
        guard !pids.isEmpty else { return [] }
        let now = ContinuousClock.now
        let user = getuid()
        var tasks: [pid_t: proc_taskinfo] = [:]
        var gaps: [pid_t] = []
        tasks.reserveCapacity(pids.count)
        for pid in pids {
            if let task = taskInfo(pid) {
                tasks[pid] = task
            } else {
                gaps.append(pid)
            }
        }
        // WindowServer and other root processes refuse PROC_PIDTASKINFO.
        // ps is setuid and holds the task-port entitlement, so it can see them.
        let privileged = gaps.isEmpty ? [:] : PSSnapshot.load()
        var next: [Int32: (ticks: UInt64, at: ContinuousClock.Instant)] = [:]
        var records: [ProcessRecord] = []
        records.reserveCapacity(pids.count)

        for pid in pids {
            let fallback = privileged[pid]
            let cpu: Double
            let resident: UInt64
            if let task = tasks[pid] {
                let ticks = task.pti_total_user &+ task.pti_total_system
                if let prior = previous[pid] {
                    cpu = CPUScale.percent(
                        deltaTicks: ticks &- prior.ticks,
                        wallNanoseconds: Self.wallNanoseconds(from: prior.at, to: now),
                        numer: tickScale.numer,
                        denom: tickScale.denom
                    )
                } else {
                    cpu = 0
                }
                next[pid] = (ticks, now)
                resident = task.pti_resident_size
            } else if let fallback {
                cpu = min(1_600, max(0, fallback.cpuPercent))
                resident = fallback.residentBytes
            } else {
                continue
            }

            var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
            let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
            let path = pathLength > 0 ? String(cString: pathBuffer) : ""
            var nameBuffer = [CChar](repeating: 0, count: 256)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)
            let command: String
            if wantsArguments(path: path, name: name) {
                command = arguments(pid) ?? (path.isEmpty ? name : path)
            } else if !path.isEmpty {
                command = path
            } else if !name.isEmpty {
                command = name
            } else {
                command = fallback?.command ?? ""
            }
            let info = bsdInfo(pid)
            let owned: Bool
            if let info {
                owned = info.uid == user
            } else if let fallback {
                owned = fallback.uid == user
            } else {
                owned = false
            }
            let label = path.isEmpty ? (name.isEmpty ? command : name) : path
            guard !label.isEmpty else { continue }
            records.append(
                ProcessRecord(
                    pid: pid,
                    parentPid: info?.ppid ?? 0,
                    residentBytes: resident,
                    cpuPercent: cpu,
                    path: label,
                    command: command.isEmpty ? label : command,
                    ownedByUser: owned
                )
            )
        }
        previous = next
        return records
    }

    private static func pids() -> [pid_t] {
        let bufferBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bufferBytes > 0 else { return [] }
        let count = Int(bufferBytes) / MemoryLayout<pid_t>.stride
        var buffer = [pid_t](repeating: 0, count: count + 16)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.stride))
        guard written > 0 else { return [] }
        let alive = Int(written) / MemoryLayout<pid_t>.stride
        return buffer.prefix(min(alive, buffer.count)).filter { $0 > 0 }
    }

    private static func wallNanoseconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> UInt64 {
        let wall = start.duration(to: end)
        let seconds = wall.components.seconds
        let nanoseconds = wall.components.attoseconds / 1_000_000_000
        guard seconds >= 0, nanoseconds >= 0 else { return 0 }
        return UInt64(seconds) * 1_000_000_000 + UInt64(nanoseconds)
    }
}

private struct BSDBrief {
    var uid: uid_t
    var ppid: pid_t
}

private func bsdInfo(_ pid: pid_t) -> BSDBrief? {
    var info = proc_bsdinfo()
    let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.stride))
    guard size > 0 else { return nil }
    return BSDBrief(uid: info.pbi_uid, ppid: pid_t(info.pbi_ppid))
}

private func taskInfo(_ pid: pid_t) -> proc_taskinfo? {
    var info = proc_taskinfo()
    let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.stride))
    guard size > 0 else { return nil }
    return info
}

private func wantsArguments(path: String, name: String) -> Bool {
    let blob = (path + " " + name).lowercased()
    return blob.contains("node") || blob.contains("mcp") || blob.contains("npx")
}

private func arguments(_ pid: pid_t) -> String? {
    var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
    var size = 0
    guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0, size < 256_000 else { return nil }
    var buffer = [UInt8](repeating: 0, count: size)
    guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
    guard size >= 4 else { return nil }
    var cursor = 4
    while cursor < size && buffer[cursor] != 0 { cursor += 1 }
    while cursor < size && buffer[cursor] == 0 { cursor += 1 }
    var parts: [String] = []
    var token: [UInt8] = []
    while cursor < size && parts.count < 24 {
        let byte = buffer[cursor]
        cursor += 1
        if byte == 0 {
            if token.isEmpty { break }
            parts.append(String(decoding: token, as: UTF8.self))
            token.removeAll(keepingCapacity: true)
        } else {
            token.append(byte)
        }
    }
    let joined = parts.joined(separator: " ")
    return joined.isEmpty ? nil : joined
}
