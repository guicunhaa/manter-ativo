import AppKit
import Darwin
import Foundation
import ManterAtivoCore

enum ActionService {
    static func terminate(family: AppFamily) -> String {
        guard family.userKillable else { return "\(family.name) fica de fora. É do sistema ou é ferramenta sua." }
        if let bundlePath = family.bundlePath {
            let url = URL(fileURLWithPath: bundlePath)
            let apps = NSWorkspace.shared.runningApplications.filter { app in
                app.bundleURL == url || app.executableURL?.path.hasPrefix(bundlePath) == true
            }
            if !apps.isEmpty {
                let ok = apps.allSatisfy { $0.terminate() }
                return ok ? "Pedi para \(family.name) encerrar." : "\(family.name) não aceitou o encerramento."
            }
        }
        let sent = signal(pids: family.pids, signo: SIGTERM)
        return "Sinal de término enviado a \(sent) processo\(sent == 1 ? "" : "s") de \(family.name)."
    }

    static func trim(set: DuplicateSet) -> String {
        let sent = signal(pids: set.extraPIDs, signo: SIGTERM)
        return "Mantive o processo \(set.keepPID) e encerrei \(sent) cópia\(sent == 1 ? "" : "s") de \(set.title)."
    }

    static func delete(categoryID: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let url = ReclaimGuard.vetDelete(home: home, categoryID: categoryID),
              let category = ReclaimCatalog.category(id: categoryID)
        else { return "Esse caminho não está na lista autorizada." }
        guard FileManager.default.fileExists(atPath: url.path) else {
            return "\(category.title) já não está no disco."
        }
        do {
            try FileManager.default.removeItem(at: url)
            return "Apaguei \(category.title). O espaço volta agora. O que for cache, o app recria."
        } catch {
            return "Não consegui apagar \(category.title): \(error.localizedDescription)"
        }
    }

    static func energy(_ choice: EnergyChoice) -> String {
        let command = (["/usr/bin/pmset"] + choice.pmsetArguments).joined(separator: " ")
        let result = admin(command)
        return result == "OK" ? "Modo de energia: \(choice.title)." : result
    }

    static func wakeOnLAN(_ enabled: Bool) -> String {
        let result = admin("/usr/bin/pmset -a womp \(enabled ? "1" : "0")")
        if result != "OK" { return result }
        return enabled ? "Wake on LAN ligado." : "Wake on LAN desligado."
    }

    static func spotlight(enabled: Bool) -> String {
        let flag = enabled ? "on" : "off"
        let result = admin("/usr/bin/mdutil -i \(flag) /")
        if result != "OK" { return result }
        return enabled ? "Spotlight indexando de novo." : "Spotlight pausado."
    }

    private static func signal(pids: [Int32], signo: Int32) -> Int {
        var sent = 0
        for pid in pids {
            guard canSignal(pid) else { continue }
            if kill(pid, signo) == 0 { sent += 1 }
        }
        return sent
    }

    private static func canSignal(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.stride))
        guard size > 0, info.pbi_uid == getuid() else { return false }
        var nameBuffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
        let name = String(cString: nameBuffer).lowercased()
        let blocked = ["kernel_task", "launchd", "windowserver", "loginwindow", "manterativo", "peripheralctl", "caffeinate"]
        if blocked.contains(name) { return false }
        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        _ = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        let path = String(cString: pathBuffer).lowercased()
        if path.contains("keepawake") || path.contains("manter ativo.app") || path.contains("peripheralctl") {
            return false
        }
        return true
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
        return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "O ajuste não foi aplicado."
            : result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
