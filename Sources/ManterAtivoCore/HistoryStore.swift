import Foundation

public struct HistoryStore: Sendable {
    public var fileURL: URL
    public var retention: TimeInterval

    public init(fileURL: URL, retention: TimeInterval = 7 * 24 * 60 * 60) {
        self.fileURL = fileURL
        self.retention = retention
    }

    public static func defaultStore() -> HistoryStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let directory = base.appendingPathComponent("Manter Ativo", isDirectory: true)
        return HistoryStore(fileURL: directory.appendingPathComponent("samples.jsonl"))
    }

    public func load() -> [HistoryPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return [] }
        let cutoff = Date().timeIntervalSince1970 - retention
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let point = try? JSONDecoder().decode(HistoryPoint.self, from: data),
                  point.t >= cutoff
            else { return nil }
            return point
        }
    }

    public func append(_ point: HistoryPoint) {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = load() + [point]
        let cutoff = Date().timeIntervalSince1970 - retention
        let kept = existing.filter { $0.t >= cutoff }
        let lines = kept.compactMap { point -> String? in
            guard let data = try? JSONEncoder().encode(point) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let body = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? body.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

public enum USBListing {
    public static func devices(from ioregOutput: String) -> [USBDeviceInfo] {
        var names: [String] = []
        for line in ioregOutput.split(whereSeparator: \.isNewline) {
            guard let quoted = String(line).sliceUSBName() else { continue }
            if !names.contains(quoted) {
                names.append(quoted)
            }
        }
        return names.map { USBDeviceInfo(id: $0, name: $0) }
    }
}

private extension String {
    func sliceUSBName() -> String? {
        guard let marker = range(of: "\"USB Product Name\" = \"") else { return nil }
        let rest = self[marker.upperBound...]
        guard let end = rest.range(of: "\"") else { return nil }
        let name = String(rest[..<end.lowerBound])
        return name.isEmpty ? nil : name
    }
}

public enum SpotlightStatus {
    public static func indexing(from mdutilOutput: String) -> Bool? {
        let lower = mdutilOutput.lowercased()
        if lower.contains("indexing disabled") || lower.contains("indexação desativada") {
            return false
        }
        if lower.contains("indexing enabled") || lower.contains("indexação ativada") {
            return true
        }
        return nil
    }
}
