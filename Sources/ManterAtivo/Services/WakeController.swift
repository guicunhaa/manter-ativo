import Foundation
import ManterAtivoCore

enum WakeController {
    static let label = "com.guicunha.keepawake"

    static func observe() -> WakeObservation {
        let pmset = Shell.run(executable: "/usr/bin/pmset", arguments: ["-g"])
        let uid = getuid()
        let agent = Shell.run(
            executable: "/bin/launchctl",
            arguments: ["print", "gui/\(uid)/\(label)"]
        )
        let helper = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/manter-ativo-on")
            && FileManager.default.fileExists(atPath: "/etc/sudoers.d/manter-ativo")
        return WakeParser.observation(
            pmsetOutput: pmset.stdout,
            agentLoaded: WakeParser.agentIsLoaded(agent.stdout + "\n" + agent.stderr),
            helperInstalled: helper
        )
    }

    static func apply(_ mode: WakeMode, helpers: URL) -> String {
        switch mode {
        case .machine:
            return enable(scriptName: "keepawake-machine.sh", helpers: helpers, armPower: true)
        case .screen:
            let power = runSudoOff()
            let agent = enable(scriptName: "keepawake-screen.sh", helpers: helpers, armPower: false)
            if let power, power != "OK" {
                return power + " " + agent
            }
            return agent
        case .off:
            let agent = stopAgent()
            let power = runSudoOff() ?? "Componente de energia não instalado."
            return [agent, power].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    static func installHelper(helpers: URL, user: String) -> String {
        let script = helpers.appendingPathComponent("install-helper.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            return "O instalador não está no app."
        }
        let command = "/bin/bash \(quote(script.path)) \(quote(helpers.path)) \(quote(user))"
        return admin(command)
    }

    private static func enable(scriptName: String, helpers: URL, armPower: Bool) -> String {
        let source = helpers.appendingPathComponent(scriptName)
        guard FileManager.default.fileExists(atPath: source.path) else {
            return "Recurso \(scriptName) não encontrado."
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keep = home.appendingPathComponent(".grok/keep-awake", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)
            backupPower(into: keep)
            let destination = keep.appendingPathComponent("keepawake.sh")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
            try writePlist(script: destination, logs: keep)
        } catch {
            return "Não consegui gravar o agente: \(error.localizedDescription)"
        }

        let uid = getuid()
        let plist = home
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
        _ = Shell.run(executable: "/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(label)"])
        let boot = Shell.run(executable: "/bin/launchctl", arguments: ["bootstrap", "gui/\(uid)", plist.path])
        _ = Shell.run(executable: "/bin/launchctl", arguments: ["enable", "gui/\(uid)/\(label)"])
        _ = Shell.run(executable: "/bin/launchctl", arguments: ["kickstart", "-k", "gui/\(uid)/\(label)"])
        if boot.status != 0 && !boot.stderr.isEmpty && !boot.stderr.contains("already bootstrapped") {
            return "Agente: \(boot.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        }
        guard armPower else { return "Vigília de tela ligada." }
        if let power = runSudoOn() {
            return power == "OK" ? "Vigília de máquina ligada." : power
        }
        return "Agente ligado. Falta instalar o componente de energia."
    }

    private static func stopAgent() -> String {
        let uid = getuid()
        _ = Shell.run(executable: "/bin/launchctl", arguments: ["bootout", "gui/\(uid)/\(label)"])
        let home = FileManager.default.homeDirectoryForCurrentUser
        let plist = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
        try? FileManager.default.removeItem(at: plist)
        let kill = Shell.run(executable: "/bin/bash", arguments: ["-c", killScript])
        if kill.status != 0 {
            return "Agente removido."
        }
        return "Agente removido."
    }

    private static func runSudoOn() -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/local/bin/manter-ativo-on") else { return nil }
        let result = Shell.run(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/local/bin/manter-ativo-on"])
        return result.status == 0 ? "OK" : trimmed(result.stderr, fallback: "O sudo da vigília falhou.")
    }

    private static func runSudoOff() -> String? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/local/bin/manter-ativo-off") else { return nil }
        let result = Shell.run(executable: "/usr/bin/sudo", arguments: ["-n", "/usr/local/bin/manter-ativo-off"])
        return result.status == 0 ? "OK" : trimmed(result.stderr, fallback: "Não consegui soltar o ajuste de energia.")
    }

    private static func backupPower(into directory: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let file = directory.appendingPathComponent("backup-\(stamp).txt")
        let general = Shell.run(executable: "/usr/bin/pmset", arguments: ["-g"])
        let custom = Shell.run(executable: "/usr/bin/pmset", arguments: ["-g", "custom"])
        let body = "# captured \(Date())\n=== pmset -g ===\n\(general.stdout)\n=== pmset -g custom ===\n\(custom.stdout)\n"
        try? body.write(to: file, atomically: true, encoding: .utf8)
        let latest = directory.appendingPathComponent("latest-backup.txt")
        try? FileManager.default.removeItem(at: latest)
        try? FileManager.default.createSymbolicLink(at: latest, withDestinationURL: file)
    }

    private static func writePlist(script: URL, logs: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let agents = home.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", script.path],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
            "StandardOutPath": logs.appendingPathComponent("keepawake.out.log").path,
            "StandardErrorPath": logs.appendingPathComponent("keepawake.err.log").path,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: agents.appendingPathComponent("\(label).plist"), options: .atomic)
    }

    private static func admin(_ command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges with prompt \"Manter Ativo precisa da sua senha para este ajuste.\""
        let result = Shell.run(executable: "/usr/bin/osascript", arguments: ["-e", source])
        if result.status == 0 { return "OK" }
        let text = (result.stderr + result.stdout).lowercased()
        if text.contains("cancel") || text.contains("(-128)") { return "Cancelado." }
        return trimmed(result.stderr, fallback: "O ajuste não foi aplicado.")
    }

    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func trimmed(_ text: String, fallback: String) -> String {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? fallback : clean
    }

    private static let killScript = """
    for pid in $(pgrep -x caffeinate || true); do
      cmd=$(ps -p "$pid" -o args= 2>/dev/null || true)
      case "$cmd" in
        *keepawake-machine*|*keepawake-screen*|*-dims*|*-u\\ -t\\ 55*|*"caffeinate -di"*)
          kill "$pid" 2>/dev/null || true
          ;;
      esac
    done
    """
}
