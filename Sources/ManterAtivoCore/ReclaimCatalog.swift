import Foundation

public struct ReclaimCategory: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var relativePath: String

    public init(id: String, title: String, detail: String, relativePath: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.relativePath = relativePath
    }
}

public enum ReclaimCatalog {
    public static let categories: [ReclaimCategory] = [
        ReclaimCategory(
            id: "after-effects",
            title: "After Effects, preview",
            detail: "Cache de preview. Apagar libera o disco agora. O próximo preview recria. O projeto fica.",
            relativePath: "Library/Caches/Adobe/After Effects"
        ),
        ReclaimCategory(
            id: "codex",
            title: "Cache do Codex",
            detail: "Cache local do Codex. A sessão seguinte recria o que precisar.",
            relativePath: "Library/Caches/Codex"
        ),
        ReclaimCategory(
            id: "edge",
            title: "Cache do Edge",
            detail: "Páginas e mídia em cache. O Edge baixa de novo o que abrir.",
            relativePath: "Library/Caches/Microsoft Edge"
        ),
        ReclaimCategory(
            id: "spotify",
            title: "Cache do Spotify",
            detail: "Áudio em cache. As faixas seguintes baixam de novo.",
            relativePath: "Library/Caches/com.spotify.client"
        ),
        ReclaimCategory(
            id: "copilot",
            title: "Cache do Copilot",
            detail: "Cache do app Copilot. Dá para recriar.",
            relativePath: "Library/Caches/copilot"
        ),
        ReclaimCategory(
            id: "homebrew",
            title: "Cache do Homebrew",
            detail: "Downloads de fórmula já instalados. O próximo upgrade baixa de novo.",
            relativePath: "Library/Caches/Homebrew"
        ),
        ReclaimCategory(
            id: "npx",
            title: "Cache do npx",
            detail: "Pacotes temporários de npx. Rodar de novo baixa outra vez.",
            relativePath: ".npm/_npx"
        ),
        ReclaimCategory(
            id: "logs",
            title: "Logs do usuário",
            detail: "Logs em ~/Library/Logs. Não inclui logs do sistema.",
            relativePath: "Library/Logs"
        ),
        ReclaimCategory(
            id: "derived-data",
            title: "DerivedData do Xcode",
            detail: "Build intermediário. O próximo build do Xcode recompila.",
            relativePath: "Library/Developer/Xcode/DerivedData"
        ),
        ReclaimCategory(
            id: "colima",
            title: "Cache do Colima",
            detail: "Cache local do Colima. Não apaga volumes de container.",
            relativePath: "Library/Caches/colima"
        ),
    ]

    public static func category(id: String) -> ReclaimCategory? {
        categories.first { $0.id == id }
    }
}

public enum ReclaimGuard {
    public static func authorizedURL(home: URL, category: ReclaimCategory) -> URL? {
        let root = home.standardizedFileURL
        var url = root
        for part in category.relativePath.split(separator: "/") {
            if part == "." || part == ".." || part.isEmpty { return nil }
            url.append(path: String(part), directoryHint: .isDirectory)
        }
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        guard isInsideHome(resolved, home: root) else { return nil }
        guard hasAllowedPrefix(resolved, home: root) else { return nil }
        let expected = expectedURL(home: root, relative: category.relativePath)
        guard resolved == expected.resolvingSymlinksInPath() || standardized == expected else { return nil }
        return standardized
    }

    public static func vetDelete(home: URL, categoryID: String) -> URL? {
        guard let category = ReclaimCatalog.category(id: categoryID) else { return nil }
        return authorizedURL(home: home, category: category)
    }

    private static func expectedURL(home: URL, relative: String) -> URL {
        var url = home.standardizedFileURL
        for part in relative.split(separator: "/") {
            url.append(path: String(part), directoryHint: .isDirectory)
        }
        return url.standardizedFileURL
    }

    private static func isInsideHome(_ url: URL, home: URL) -> Bool {
        let homePath = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return url.path.hasPrefix(homePath)
    }

    private static func hasAllowedPrefix(_ url: URL, home: URL) -> Bool {
        let prefixes = [
            "Library/Caches/",
            "Library/Logs/",
            "Library/Developer/Xcode/DerivedData/",
            ".npm/_npx/",
        ]
        let homePath = home.path.hasSuffix("/") ? home.path : home.path + "/"
        return prefixes.contains { prefix in
            url.path.hasPrefix(homePath + prefix) || url.path + "/" == homePath + prefix
        }
    }
}

public enum ReclaimMeasure {
    public static func measure(home: URL) -> [ReclaimItem] {
        ReclaimCatalog.categories.map { category in
            guard let url = ReclaimGuard.authorizedURL(home: home, category: category) else {
                return ReclaimItem(id: category.id, title: category.title, detail: category.detail, bytes: 0, exists: false)
            }
            let exists = FileManager.default.fileExists(atPath: url.path)
            let bytes = exists ? directoryBytes(url) : 0
            return ReclaimItem(id: category.id, title: category.title, detail: category.detail, bytes: bytes, exists: exists)
        }
    }

    public static func directoryBytes(_ url: URL) -> UInt64 {
        let result = Shell.run(executable: "/usr/bin/du", arguments: ["-sk", url.path])
        guard result.status == 0 else { return 0 }
        let first = result.stdout.split(whereSeparator: \.isWhitespace).first
        guard let text = first, let kib = UInt64(text) else { return 0 }
        return kib * 1024
    }

    public static func importantFreeBytes(at url: URL = FileManager.default.homeDirectoryForCurrentUser) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        let values = try? url.resourceValues(forKeys: keys)
        return values?.volumeAvailableCapacityForImportantUsage
    }
}
