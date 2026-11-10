import Foundation

public enum FamilyNamer {
    public static func name(path: String, command: String, rules: [AgentRule] = []) -> String {
        if let agent = agentTitle(command: command, path: path, rules: rules) {
            return agent
        }
        return processName(path: path)
    }

    fileprivate static func processName(path: String) -> String {
        if let app = outermostApp(path: path) {
            return app
        }
        let base = path.isEmpty ? "" : URL(fileURLWithPath: path).lastPathComponent
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
            return base.isEmpty ? "Processo" : base
        }
    }

    public static func isSystem(_ name: String) -> Bool {
        [
            "Spotlight",
            "WindowServer",
            "kernel_task",
            "caffeinate",
            "launchd",
            "loginwindow",
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

    public static func agentTitle(command: String, path: String = "", rules: [AgentRule] = []) -> String? {
        identify(command: command, path: path, rules: rules)?.title
    }

    public static func duplicateKey(command: String, path: String = "", rules: [AgentRule] = []) -> String? {
        identify(command: command, path: path, rules: rules)?.key
    }

    fileprivate struct AgentIdentity {
        var title: String
        var key: String
    }

    fileprivate static func identify(command: String, path: String, rules: [AgentRule]) -> AgentIdentity? {
        if let rule = matching(command, rules: rules) {
            return AgentIdentity(title: rule.title, key: rule.key)
        }
        let lower = command.lowercased()
        if lower.contains("after-effects-mcp") {
            return AgentIdentity(title: "After Effects MCP", key: "after-effects-mcp")
        }
        if lower.contains("mcp-server-asana") {
            return AgentIdentity(title: "Asana MCP", key: "asana-mcp")
        }
        if lower.contains("@hostinger/mcp") || (lower.contains("hostinger") && lower.contains("mcp")) {
            return AgentIdentity(title: "VPS MCP", key: "hostinger-mcp")
        }
        if let assistant = assistantIdentity(path: path) {
            return assistant
        }
        if !path.lowercased().contains(".app"), let coder = codingIdentity(path: path, command: command) {
            return coder
        }
        if let mcp = genericMCP(command: command, path: path) {
            // Ferramenta sem nome dentro de um .app pertence ao app. Não vira outra cópia.
            if mcp.key.hasPrefix("servidor-mcp-"), path.lowercased().contains(".app/") {
                return nil
            }
            return mcp
        }
        return nil
    }

    /// App de assistente que contém este processo, mesmo quando o processo não é o executável principal.
    static func hostAssistant(path: String) -> (title: String, key: String)? {
        guard let outer = outermostApp(path: path)?.lowercased() else { return nil }
        guard let identity = assistantApps[outer] else { return nil }
        return (identity.title, identity.key)
    }

    private static let assistantApps: [String: AgentIdentity] = [
        "chatgpt": AgentIdentity(title: "ChatGPT", key: "chatgpt"),
        "claude": AgentIdentity(title: "Claude", key: "claude-app"),
        "codex": AgentIdentity(title: "Codex", key: "codex-app"),
        "cursor": AgentIdentity(title: "Cursor", key: "cursor"),
        "windsurf": AgentIdentity(title: "Windsurf", key: "windsurf"),
        "perplexity": AgentIdentity(title: "Perplexity", key: "perplexity"),
        "copilot": AgentIdentity(title: "Copilot", key: "copilot"),
        "gemini": AgentIdentity(title: "Gemini", key: "gemini-app"),
    ]

    private static func assistantIdentity(path: String) -> AgentIdentity? {
        guard let outer = outermostApp(path: path), let own = ownApp(path: path) else { return nil }
        guard outer.caseInsensitiveCompare(own) == .orderedSame else { return nil }
        guard isMainAppExecutable(path: path, app: own) else { return nil }
        return assistantApps[outer.lowercased()]
    }

    /// Só o executável principal. Ferramenta dentro de Resources não é outra cópia do app.
    private static func isMainAppExecutable(path: String, app: String) -> Bool {
        let lower = path.lowercased()
        let marker = "\(app.lowercased()).app/contents/macos/"
        guard let range = lower.range(of: marker) else { return false }
        let executable = lower[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        return executable == app.lowercased()
    }

    private static func ownApp(path: String) -> String? {
        for part in path.split(separator: "/").reversed() where part.hasSuffix(".app") {
            let name = part.dropLast(4)
            if !name.isEmpty { return String(name) }
        }
        return nil
    }

    private static let codingAgents: [(names: Set<String>, identity: AgentIdentity)] = [
        (["claude", "claude-code"], AgentIdentity(title: "Claude Code", key: "claude-code")),
        (["codex"], AgentIdentity(title: "Codex", key: "codex")),
        (["aider"], AgentIdentity(title: "Aider", key: "aider")),
        (["cursor-agent"], AgentIdentity(title: "Cursor Agent", key: "cursor-agent")),
        (["goose"], AgentIdentity(title: "Goose", key: "goose")),
        (["opencode"], AgentIdentity(title: "OpenCode", key: "opencode")),
        (["openhands"], AgentIdentity(title: "OpenHands", key: "openhands")),
        (["crush"], AgentIdentity(title: "Crush", key: "crush")),
        (["gemini"], AgentIdentity(title: "Gemini CLI", key: "gemini-cli")),
        (["swe-agent", "sweagent"], AgentIdentity(title: "SWE Agent", key: "swe-agent")),
        (["cody"], AgentIdentity(title: "Cody", key: "cody")),
        (["amp"], AgentIdentity(title: "Amp", key: "amp")),
        (["continue"], AgentIdentity(title: "Continue", key: "continue")),
        (["qwen"], AgentIdentity(title: "Qwen", key: "qwen")),
        (["kilocode"], AgentIdentity(title: "Kilo Code", key: "kilocode")),
    ]

    private static func codingIdentity(path: String, command: String) -> AgentIdentity? {
        let names = Set(executableBasenames(path: path, command: command))
        return codingAgents.first { !$0.names.isDisjoint(with: names) }?.identity
    }

    private static func executableBasenames(path: String, command: String) -> [String] {
        var names: [String] = []
        let pathBase = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        if !pathBase.isEmpty { names.append(pathBase) }
        if let first = command.split(whereSeparator: \.isWhitespace).first {
            let base = URL(fileURLWithPath: String(first)).lastPathComponent.lowercased()
            if !base.isEmpty { names.append(base) }
        }
        return names
    }

    private static func genericMCP(command: String, path: String) -> AgentIdentity? {
        let blob = (path + "\n" + command).lowercased()
        guard blob.contains("mcp") else { return nil }
        let server = blob.contains("mcp-server")
            || blob.contains("mcp_server")
            || blob.contains("-mcp")
            || blob.contains("_mcp")
            || blob.contains("/mcp")
            || blob.contains(" mcp")
            || blob.contains("mcp ")
            || (blob.contains("@") && blob.contains("mcp"))
        guard server else { return nil }
        let stamp = stableStamp(unnamedBasis(command: command, path: path))
        return AgentIdentity(title: "Servidor MCP", key: "servidor-mcp-\(stamp)")
    }

    /// Assinatura estável sem segredo e sem colapsar todo mundo no binário `node`.
    private static func unnamedBasis(command: String, path: String) -> String {
        var kept: [String] = []
        var skipValue = false
        for part in command.lowercased().split(whereSeparator: \.isWhitespace) {
            if skipValue {
                skipValue = false
                continue
            }
            let sensitive = ["token", "secret", "session", "password", "cookie", "bearer", "api-key"]
            if part.hasPrefix("-"), sensitive.contains(where: { part.contains($0) }) {
                skipValue = !part.contains("=")
                continue
            }
            if !part.contains("="), part.count <= 256 { kept.append(String(part)) }
        }
        return kept.isEmpty ? path : kept.joined(separator: " ")
    }

    private static func stableStamp(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
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
    ) -> GroupedProcesses {
        struct Bucket {
            var name: String
            var bytes: UInt64 = 0
            var cpu: Double = 0
            var pids: [Int32] = []
            var bundlePath: String?
            var protected = false
            var owned = true
        }

        struct AgentBucket {
            var title: String
            var bytes: UInt64 = 0
            var cpu: Double = 0
            var members: [(pid: Int32, parent: Int32)] = []
            var protected = false
            var owned = true
        }

        var buckets: [String: Bucket] = [:]
        var agentBuckets: [String: AgentBucket] = [:]

        for record in records {
            let identity = FamilyNamer.identify(command: record.command, path: record.path, rules: rules)
            let name = identity?.title ?? FamilyNamer.processName(path: record.path)
            let key = identity.map { $0.title == "Servidor MCP" ? $0.key : name } ?? name
            var bucket = buckets[key] ?? Bucket(name: name)
            bucket.bytes += record.residentBytes
            bucket.cpu += record.cpuPercent
            bucket.pids.append(record.pid)
            bucket.protected = bucket.protected || FamilyNamer.isProtected(path: record.path, command: record.command)
            bucket.owned = bucket.owned && record.ownedByUser
            if bucket.bundlePath == nil, let app = FamilyNamer.outermostApp(path: record.path), app == name {
                if let range = record.path.range(of: app + ".app") {
                    let end = record.path.index(range.upperBound, offsetBy: 0)
                    bucket.bundlePath = String(record.path[..<end])
                }
            }
            buckets[key] = bucket

            if let identity {
                let key = identity.key
                let title = identity.title
                var agent = agentBuckets[key] ?? AgentBucket(title: title)
                agent.bytes += record.residentBytes
                agent.cpu += record.cpuPercent
                agent.members.append((record.pid, record.parentPid))
                agent.protected = agent.protected || FamilyNamer.isProtected(path: record.path, command: record.command)
                agent.owned = agent.owned && record.ownedByUser
                agentBuckets[key] = agent
            }
        }

        let claimed = Set(agentBuckets.values.flatMap { $0.members.map(\.pid) })
        for record in records where !claimed.contains(record.pid) {
            guard let host = FamilyNamer.hostAssistant(path: record.path) else { continue }
            var agent = agentBuckets[host.key] ?? AgentBucket(title: host.title)
            agent.bytes += record.residentBytes
            agent.cpu += record.cpuPercent
            agent.members.append((record.pid, record.parentPid))
            agent.protected = agent.protected || FamilyNamer.isProtected(path: record.path, command: record.command)
            agent.owned = agent.owned && record.ownedByUser
            agentBuckets[host.key] = agent
        }

        let families = buckets
            .filter { _, bucket in bucket.bytes >= 40 * 1024 * 1024 || bucket.cpu >= 8 || bucket.name == "Spotlight" }
            .map { key, bucket in
                AppFamily(
                    id: key,
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

        func copyPIDs(_ bucket: AgentBucket) -> [Int32] {
            let inside = Set(bucket.members.map(\.pid))
            let roots = bucket.members.filter { !inside.contains($0.parent) }.map(\.pid).sorted()
            if !roots.isEmpty { return roots }
            return bucket.members.map(\.pid).sorted()
        }

        let agents = agentBuckets.map { key, bucket in
            let copies = copyPIDs(bucket)
            let keep = copies.first ?? 0
            return AgentSighting(
                id: key,
                title: bucket.title,
                cpuPercent: bucket.cpu,
                residentBytes: bucket.bytes,
                copyCount: copies.count,
                keepPID: keep,
                extraPIDs: Array(copies.dropFirst()),
                userKillable: bucket.owned && !bucket.protected && !FamilyNamer.isSystem(bucket.title)
            )
        }
        .sorted { lhs, rhs in
            if lhs.residentBytes == rhs.residentBytes { return (lhs.title, lhs.id) < (rhs.title, rhs.id) }
            return lhs.residentBytes > rhs.residentBytes
        }

        let duplicates = agents.filter { $0.userKillable && $0.copyCount > 1 }.map { agent in
            DuplicateSet(id: agent.id, title: agent.title, count: agent.copyCount,
                         residentBytes: agent.residentBytes, keepPID: agent.keepPID, extraPIDs: agent.extraPIDs)
        }
        return GroupedProcesses(families: families, duplicates: duplicates, agents: agents)
    }
}

public struct AgentSighting: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var cpuPercent: Double
    public var residentBytes: UInt64
    public var copyCount: Int
    public var keepPID: Int32
    public var extraPIDs: [Int32]
    public var userKillable: Bool

    public init(
        id: String,
        title: String,
        cpuPercent: Double,
        residentBytes: UInt64,
        copyCount: Int,
        keepPID: Int32,
        extraPIDs: [Int32],
        userKillable: Bool
    ) {
        self.id = id
        self.title = title
        self.cpuPercent = cpuPercent
        self.residentBytes = residentBytes
        self.copyCount = copyCount
        self.keepPID = keepPID
        self.extraPIDs = extraPIDs
        self.userKillable = userKillable
    }
}

public struct GroupedProcesses: Sendable, Equatable {
    public var families: [AppFamily]
    public var duplicates: [DuplicateSet]
    public var agents: [AgentSighting]

    public init(families: [AppFamily], duplicates: [DuplicateSet], agents: [AgentSighting]) {
        self.families = families
        self.duplicates = duplicates
        self.agents = agents
    }
}

public enum AgentBar {
    public struct Row: Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var cpuPercent: Double
        public var residentBytes: UInt64
        public var copyCount: Int
        public var cpuText: String
        public var memoryText: String
        public var copiesText: String

        public init(
            id: String,
            title: String,
            cpuPercent: Double,
            residentBytes: UInt64,
            copyCount: Int,
            cpuText: String,
            memoryText: String,
            copiesText: String
        ) {
            self.id = id
            self.title = title
            self.cpuPercent = cpuPercent
            self.residentBytes = residentBytes
            self.copyCount = copyCount
            self.cpuText = cpuText
            self.memoryText = memoryText
            self.copiesText = copiesText
        }
    }

    public struct Snapshot: Sendable, Equatable {
        public var sectionTitle: String
        public var rows: [Row]
        public var openPanelTitle: String
        public var quitTitle: String
        public var quitLeavesWakeOn: Bool
        public var killableNames: [String]

        public init(
            sectionTitle: String,
            rows: [Row],
            openPanelTitle: String,
            quitTitle: String,
            quitLeavesWakeOn: Bool,
            killableNames: [String]
        ) {
            self.sectionTitle = sectionTitle
            self.rows = rows
            self.openPanelTitle = openPanelTitle
            self.quitTitle = quitTitle
            self.quitLeavesWakeOn = quitLeavesWakeOn
            self.killableNames = killableNames
        }

        public static let empty = Snapshot(
            sectionTitle: "Agentes",
            rows: [],
            openPanelTitle: "Abrir painel",
            quitTitle: "Sair (vigília fica)",
            quitLeavesWakeOn: true,
            killableNames: []
        )
    }

    public static func snapshot(_ grouped: GroupedProcesses) -> Snapshot {
        let rows = grouped.agents.map { agent in
            Row(
                id: agent.id,
                title: agent.title,
                cpuPercent: agent.cpuPercent,
                residentBytes: agent.residentBytes,
                copyCount: agent.copyCount,
                cpuText: PTFormat.percent(agent.cpuPercent, digits: 1),
                memoryText: PTFormat.bytes(agent.residentBytes),
                copiesText: agent.copyCount == 1 ? "1 cópia" : "\(agent.copyCount) cópias"
            )
        }
        return Snapshot(
            sectionTitle: "Agentes",
            rows: rows,
            openPanelTitle: "Abrir painel",
            quitTitle: "Sair (vigília fica)",
            quitLeavesWakeOn: true,
            killableNames: grouped.families.filter(\.userKillable).map(\.name)
        )
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
