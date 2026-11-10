import Foundation

public enum FamilyNamer {
    public static func name(path: String, command: String, rules: [AgentRule] = []) -> String {
        if let agent = agentTitle(command: command, rules: rules) {
            return agent
        }
        if let app = outermostApp(path: path) {
            return app
        }
        let base = URL(fileURLWithPath: path.isEmpty ? command : path).lastPathComponent
        switch base {
        case "mds_stores", "mds", "mdworker", "mdworker_shared", "corespotlightd":
            return "Spotlight"
        case "CGPDFService":
            return "Render de PDF"
        case "WindowServer":
            return "WindowServer"
        case "kernel_task":
            return "kernel_task"
        case "coreaudiod":
            return "Áudio do sistema"
        default:
            return base.isEmpty ? "Processo \(command)" : base
        }
    }

    public static func isSystem(_ name: String) -> Bool {
        [
            "Spotlight",
            "WindowServer",
            "kernel_task",
            "launchd",
            "Render de PDF",
            "Áudio do sistema",
            "WindowManager",
            "sysmond",
        ].contains(name)
    }

    public static func isProtected(path: String, command: String) -> Bool {
        let blob = (path + "\n" + command).lowercased()
        let needles = [
            "manterativo",
            "manter ativo.app",
            "peripheralctl",
            "keepawake-machine",
            "keepawake-screen",
            "com.guicunha.keepawake",
        ]
        return needles.contains { blob.contains($0) }
    }

    public static func outermostApp(path: String) -> String? {
        for part in path.split(separator: "/") where part.hasSuffix(".app") {
            let name = part.dropLast(4)
            if !name.isEmpty { return String(name) }
        }
        return nil
    }

    public static func agentTitle(command: String, rules: [AgentRule] = []) -> String? {
        if let rule = matching(command, rules: rules) { return rule.title }
        let lower = command.lowercased()
        if lower.contains("after-effects-mcp") { return "After Effects MCP" }
        if lower.contains("mcp-server-asana") { return "Asana MCP" }
        if lower.contains("@hostinger/mcp") || (lower.contains("hostinger") && lower.contains("mcp")) {
            return "VPS MCP"
        }
        return nil
    }

    public static func duplicateKey(command: String, rules: [AgentRule] = []) -> String? {
        if let rule = matching(command, rules: rules) { return rule.key }
        let lower = command.lowercased()
        if lower.contains("after-effects-mcp") { return "after-effects-mcp" }
        if lower.contains("mcp-server-asana") { return "asana-mcp" }
        if lower.contains("@hostinger/mcp") || (lower.contains("hostinger") && lower.contains("mcp")) {
            return "hostinger-mcp"
        }
        return nil
    }

    private static func matching(_ command: String, rules: [AgentRule]) -> AgentRule? {
        let lower = command.lowercased()
        return rules.first { rule in
            rule.match.allSatisfy { lower.contains($0.lowercased()) }
        }
    }

    public static func normalize(_ command: String) -> String {
        var text = command
        if let regex = try? NSRegularExpression(pattern: #"/var/folders/\S+/T/\.tmp\S+"#) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "TMP"
            )
        }
        if let regex = try? NSRegularExpression(pattern: #"--session-id\s+\S+"#) {
            text = regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: "--session-id ID"
            )
        }
        return text
    }
}

public enum ProcessGrouper {
    public static func group(
        _ records: [ProcessRecord],
        rules: [AgentRule] = AgentCatalog.load()
    ) -> (families: [AppFamily], duplicates: [DuplicateSet]) {
        struct Bucket {
            var name: String
            var bytes: UInt64 = 0
            var cpu: Double = 0
            var pids: [Int32] = []
            var bundlePath: String?
            var protected = false
            var owned = true
        }

        var buckets: [String: Bucket] = [:]
        var duplicateBuckets: [String: [(pid: Int32, bytes: UInt64, title: String)]] = [:]

        for record in records {
            let name = FamilyNamer.name(path: record.path, command: record.command, rules: rules)
            var bucket = buckets[name] ?? Bucket(name: name)
            bucket.bytes += record.residentBytes
            bucket.cpu += record.cpuPercent
            bucket.pids.append(record.pid)
            bucket.protected = bucket.protected || FamilyNamer.isProtected(path: record.path, command: record.command)
            bucket.owned = bucket.owned && record.ownedByUser
            if bucket.bundlePath == nil, let app = FamilyNamer.outermostApp(path: record.path) {
                if let range = record.path.range(of: app + ".app") {
                    let end = record.path.index(range.upperBound, offsetBy: 0)
                    bucket.bundlePath = String(record.path[..<end])
                }
            }
            buckets[name] = bucket

            if record.ownedByUser, let key = FamilyNamer.duplicateKey(command: record.command, rules: rules) {
                let title = FamilyNamer.agentTitle(command: record.command, rules: rules) ?? name
                duplicateBuckets[key, default: []].append((record.pid, record.residentBytes, title))
            }
        }

        let families = buckets.values
            .filter { $0.bytes >= 40 * 1024 * 1024 || $0.cpu >= 8 || $0.name == "Spotlight" }
            .map { bucket in
                AppFamily(
                    id: bucket.name,
                    name: bucket.name,
                    residentBytes: bucket.bytes,
                    cpuPercent: bucket.cpu,
                    processCount: bucket.pids.count,
                    pids: bucket.pids.sorted(),
                    bundlePath: bucket.bundlePath,
                    userKillable: bucket.owned && !bucket.protected && !FamilyNamer.isSystem(bucket.name)
                )
            }
            .sorted { $0.residentBytes > $1.residentBytes }

        let duplicates = duplicateBuckets.compactMap { key, items -> DuplicateSet? in
            let generic = key.hasPrefix("mcp:")
            let minimum = generic ? 3 : 2
            guard items.count >= minimum else { return nil }
            let ordered = items.sorted { $0.pid < $1.pid }
            guard let keep = ordered.first else { return nil }
            let extras = ordered.dropFirst().map(\.pid)
            guard !extras.isEmpty else { return nil }
            let bytes = items.reduce(UInt64(0)) { $0 + $1.bytes }
            return DuplicateSet(
                id: key,
                title: keep.title,
                count: items.count,
                residentBytes: bytes,
                keepPID: keep.pid,
                extraPIDs: extras
            )
        }
        .sorted { $0.residentBytes > $1.residentBytes }

        return (families, duplicates)
    }
}

public struct AgentRule: Codable, Equatable, Sendable {
    public var match: [String]
    public var title: String
    public var key: String

    public init(match: [String], title: String, key: String) {
        self.match = match
        self.title = title
        self.key = key
    }
}

public enum AgentCatalog {
    public static func load(
        from url: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Manter Ativo/agentes.json")
    ) -> [AgentRule] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([AgentRule].self, from: data)) ?? []
    }
}
