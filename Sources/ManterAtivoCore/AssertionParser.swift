import Foundation

public enum AssertionParser {
    public static func holders(from pmsetOutput: String) -> [SleepHolder] {
        var holders: [SleepHolder] = []
        var seen: Set<String> = []
        let lines = pmsetOutput.split(whereSeparator: \.isNewline).map(String.init)
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if let holder = processHolder(line: line, next: index + 1 < lines.count ? lines[index + 1] : "") {
                if seen.insert(holder.id).inserted {
                    holders.append(holder)
                }
            }
            if let usb = kernelHolder(line: line) {
                if seen.insert(usb.id).inserted {
                    holders.append(usb)
                }
            }
            index += 1
        }
        return holders
    }

    private static func processHolder(line: String, next: String) -> SleepHolder? {
        guard line.contains("(pid") || line.contains("pid ") else { return nil }
        guard let nameRange = line.range(of: #"pid \d+\(([^)]+)\)"#, options: .regularExpression) else {
            return nil
        }
        let raw = String(line[nameRange])
        let process = raw.slice(between: "(", and: ")") ?? raw
        let named = line.slice(between: "named: \"", and: "\"") ?? ""
        let interesting = line.contains("Sleep") || line.contains("NoIdle") || line.contains("BackgroundTask") || line.contains("DiskIdle")
        guard interesting else { return nil }
        if process == "powerd" || process == "WindowServer" || process.hasPrefix("rcd") {
            return nil
        }

        let title = titleFor(process: process, named: named, detail: next)
        let detail = detailFor(process: process, named: named, next: next)
        return SleepHolder(id: "proc:" + title, title: title, detail: detail)
    }

    private static func titleFor(process: String, named: String, detail: String) -> String {
        let blob = (process + " " + named + " " + detail).lowercased()
        if process == "caffeinate" { return "Manter Ativo" }
        if blob.contains("handoff") { return "Handoff" }
        if process == "mds_stores" || process.contains("mds") { return "Spotlight" }
        if blob.contains("audio") || process == "coreaudiod" { return "Microfone" }
        if process.lowercased().hasPrefix("grok") { return "Grok" }
        if process == "ChatGPT" || blob.contains("chatgpt") || blob.contains("electron") && process == "ChatGPT" {
            return "ChatGPT"
        }
        return process
    }

    private static func detailFor(process: String, named: String, next: String) -> String {
        if process == "caffeinate" {
            return "O caffeinate da vigília está segurando o sono."
        }
        if !named.isEmpty { return named }
        let trimmed = next.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Impede o sono ocioso." : trimmed
    }

    private static func kernelHolder(line: String) -> SleepHolder? {
        guard line.contains("owner=") else { return nil }
        let owner = line.slice(after: "owner=") ?? ""
        let clean = owner.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        if line.contains("0x4=USB") || line.contains("=USB ") || line.contains("USB creat") || line.contains(" 0x4=USB") {
            return SleepHolder(id: "usb:" + clean, title: clean, detail: "USB ligado. Pode segurar o sono.")
        }
        if line.contains("MAGICWAKE") {
            return SleepHolder(
                id: "womp:" + clean,
                title: "Wake on LAN",
                detail: "A rede pode acordar o Mac. Porta \(clean)."
            )
        }
        return nil
    }
}

public enum WakeParser {
    public static func flags(from pmsetOutput: String) -> PowerFlags {
        PowerFlags(
            sleepDisabled: firstInt(in: pmsetOutput, label: "SleepDisabled") == 1,
            wakeOnLAN: firstInt(in: pmsetOutput, label: "womp") == 1,
            powermode: firstInt(in: pmsetOutput, label: "powermode")
        )
    }

    public static func observation(
        pmsetOutput: String,
        agentLoaded: Bool,
        helperInstalled: Bool
    ) -> WakeObservation {
        let flags = flags(from: pmsetOutput)
        let mode: WakeMode
        if flags.sleepDisabled {
            mode = .machine
        } else if agentLoaded {
            mode = .screen
        } else {
            mode = .off
        }
        return WakeObservation(
            mode: mode,
            agentLoaded: agentLoaded,
            helperInstalled: helperInstalled,
            flags: flags
        )
    }

    public static func agentIsLoaded(_ launchctlOutput: String) -> Bool {
        let text = launchctlOutput.lowercased()
        if text.contains("could not find service") || text.contains("no such process") {
            return false
        }
        return text.contains("state = running") || text.contains("com.guicunha.keepawake")
    }

    private static func firstInt(in text: String, label: String) -> Int? {
        let pattern = #"\#(NSRegularExpression.escapedPattern(for: label))\s+(-?\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text)
        else { return nil }
        return Int(text[valueRange])
    }
}

private extension String {
    func slice(between start: String, and end: String) -> String? {
        guard let lower = range(of: start) else { return nil }
        let rest = self[lower.upperBound...]
        guard let upper = rest.range(of: end) else { return nil }
        return String(rest[..<upper.lowerBound])
    }

    func slice(after marker: String) -> String? {
        guard let range = range(of: marker) else { return nil }
        return String(self[range.upperBound...])
    }
}
