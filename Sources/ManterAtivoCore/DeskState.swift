import Foundation

public struct DeskFamily: Codable, Equatable, Sendable {
    public var nome: String
    public var ram: UInt64
    public var cpu: Double
    public var processos: Int
    public var podeEncerrar: Bool

    public init(nome: String, ram: UInt64, cpu: Double, processos: Int, podeEncerrar: Bool) {
        self.nome = nome
        self.ram = ram
        self.cpu = cpu
        self.processos = processos
        self.podeEncerrar = podeEncerrar
    }
}

public struct DeskDuplicate: Codable, Equatable, Sendable {
    public var titulo: String
    public var copias: Int
    public var ram: UInt64

    public init(titulo: String, copias: Int, ram: UInt64) {
        self.titulo = titulo
        self.copias = copias
        self.ram = ram
    }
}

public struct DeskAgent: Codable, Equatable, Sendable {
    public var titulo: String
    public var cpu: Double
    public var ram: UInt64
    public var copias: Int

    public init(titulo: String, cpu: Double, ram: UInt64, copias: Int) {
        self.titulo = titulo
        self.cpu = cpu
        self.ram = ram
        self.copias = copias
    }
}

/// Retrato largo da máquina, sem caminhos de arquivo.
public struct DeskState: Codable, Equatable, Sendable {
    public var atualizado: Date
    public var frase: String
    public var vigilia: String
    public var vigiliaConhecida: Bool
    public var cpuTotal: Double?
    public var cpuSuper: Double?
    public var cpuPerformance: Double?
    public var carga: Double
    public var memoriaUsada: UInt64
    public var memoriaLivre: UInt64
    public var compressor: UInt64
    public var pressao: String
    public var swapUsado: UInt64
    public var swapTotal: UInt64
    public var swapCriptografado: Bool
    public var bateriaPercent: Int?
    public var ciclos: Int?
    public var saude: Double?
    public var cargaSegurada: Bool?
    public var adaptadorWatts: Int?
    public var cargaSistema: String?
    public var termico: String
    public var discoLivre: Int64?
    public var telas: [String]
    public var usb: [String]
    public var segurandoSono: [String]
    public var familias: [DeskFamily]
    public var agentesRepetidos: [DeskDuplicate]
    public var agentes: [DeskAgent]
    public var perfilSugerido: String?
    public var spotlight: Bool?
    public var versao: String

    public init(
        atualizado: Date,
        frase: String,
        vigilia: String,
        vigiliaConhecida: Bool,
        cpuTotal: Double?,
        cpuSuper: Double?,
        cpuPerformance: Double?,
        carga: Double,
        memoriaUsada: UInt64,
        memoriaLivre: UInt64,
        compressor: UInt64,
        pressao: String,
        swapUsado: UInt64,
        swapTotal: UInt64,
        swapCriptografado: Bool,
        bateriaPercent: Int?,
        ciclos: Int?,
        saude: Double?,
        cargaSegurada: Bool?,
        adaptadorWatts: Int?,
        cargaSistema: String?,
        termico: String,
        discoLivre: Int64?,
        telas: [String],
        usb: [String],
        segurandoSono: [String],
        familias: [DeskFamily],
        agentesRepetidos: [DeskDuplicate],
        agentes: [DeskAgent],
        perfilSugerido: String?,
        spotlight: Bool?,
        versao: String
    ) {
        self.atualizado = atualizado
        self.frase = frase
        self.vigilia = vigilia
        self.vigiliaConhecida = vigiliaConhecida
        self.cpuTotal = cpuTotal
        self.cpuSuper = cpuSuper
        self.cpuPerformance = cpuPerformance
        self.carga = carga
        self.memoriaUsada = memoriaUsada
        self.memoriaLivre = memoriaLivre
        self.compressor = compressor
        self.pressao = pressao
        self.swapUsado = swapUsado
        self.swapTotal = swapTotal
        self.swapCriptografado = swapCriptografado
        self.bateriaPercent = bateriaPercent
        self.ciclos = ciclos
        self.saude = saude
        self.cargaSegurada = cargaSegurada
        self.adaptadorWatts = adaptadorWatts
        self.cargaSistema = cargaSistema
        self.termico = termico
        self.discoLivre = discoLivre
        self.telas = telas
        self.usb = usb
        self.segurandoSono = segurandoSono
        self.familias = familias
        self.agentesRepetidos = agentesRepetidos
        self.agentes = agentes
        self.perfilSugerido = perfilSugerido
        self.spotlight = spotlight
        self.versao = versao
    }
}

public enum DeskStateStore {
    /// Pasta do projeto, se ele estiver em ~/Developer/Manter Ativo.
    /// Senão, Application Support. `MANTER_ATIVO_STATE` ganha dos dois.
    public static var liveDirectory: URL {
        let files = FileManager.default
        if let override = ProcessInfo.processInfo.environment["MANTER_ATIVO_STATE"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let home = files.homeDirectoryForCurrentUser
        let project = home.appendingPathComponent("Developer/Manter Ativo", isDirectory: true)
        if files.fileExists(atPath: project.appendingPathComponent("Package.swift").path) {
            return project.appendingPathComponent("var", isDirectory: true)
        }
        return home.appendingPathComponent("Library/Application Support/Manter Ativo", isDirectory: true)
    }

    public static func write(_ state: DeskState, to directory: URL = liveDirectory) {
        let state = sanitized(state)
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: directory.appendingPathComponent("estado.json"), options: .atomic)
        try? Data(markdown(state).utf8).write(to: directory.appendingPathComponent("estado.md"), options: .atomic)
    }

    /// Tira caminho, comando e nome de script. O harness descreve a máquina, não os projetos.
    static func sanitized(_ state: DeskState) -> DeskState {
        var copy = state
        copy.frase = scrub(state.frase) ?? "Leitura omitida."
        copy.vigilia = scrub(state.vigilia) ?? "desconhecida"
        copy.cargaSistema = state.cargaSistema.flatMap(scrub)
        copy.termico = scrub(state.termico) ?? "Sem leitura"
        copy.pressao = scrub(state.pressao) ?? "Sem leitura"
        copy.perfilSugerido = state.perfilSugerido.flatMap(scrub)
        copy.telas = state.telas.compactMap(scrub)
        copy.usb = state.usb.compactMap(scrub)
        copy.segurandoSono = state.segurandoSono.compactMap(scrub)
        copy.familias = state.familias.compactMap { family in
            guard let nome = scrub(family.nome) else { return nil }
            var clean = family
            clean.nome = nome
            return clean
        }
        copy.agentesRepetidos = state.agentesRepetidos.compactMap { set in
            guard let titulo = scrub(set.titulo) else { return nil }
            var clean = set
            clean.titulo = titulo
            return clean
        }
        copy.agentes = state.agentes.compactMap { agent in
            guard let titulo = scrub(agent.titulo) else { return nil }
            var clean = agent
            clean.titulo = titulo
            return clean
        }
        return copy
    }

    private static func scrub(_ text: String) -> String? {
        let lowered = text.lowercased()
        if text.contains("/") || lowered.contains(".mjs") || lowered.contains(".app/") {
            return nil
        }
        return text
    }

    public static func markdown(_ state: DeskState) -> String {
        let state = sanitized(state)
        let when = state.atualizado.formatted(date: .abbreviated, time: .standard)
        let cpu = state.cpuTotal.map { PTFormat.percent($0) } ?? "—"
        let superCPU = state.cpuSuper.map { PTFormat.percent($0) } ?? "—"
        let perfCPU = state.cpuPerformance.map { PTFormat.percent($0) } ?? "—"
        let battery = state.bateriaPercent.map { "\($0)%" } ?? "—"
        let hold = state.cargaSegurada == true ? "carga segurada" : "sem trava de carga"
        let disk = state.discoLivre.map { PTFormat.bytes($0) } ?? "—"
        let families = state.familias.prefix(12).map { family in
            "- \(family.nome) — \(PTFormat.bytes(family.ram)) · \(PTFormat.percent(family.cpu, digits: 1)) · \(family.processos) processos"
        }.joined(separator: "\n")
        let duplicates = state.agentesRepetidos.map { set in
            "- \(set.titulo) — \(set.copias) cópias · \(PTFormat.bytes(set.ram))"
        }.joined(separator: "\n")
        let liveAgents = state.agentes.map { agent in
            let copies = agent.copias == 1 ? "1 cópia" : "\(agent.copias) cópias"
            return "- \(agent.titulo) — \(PTFormat.percent(agent.cpu, digits: 1)) · \(PTFormat.bytes(agent.ram)) · \(copies)"
        }.joined(separator: "\n")
        let holders = state.segurandoSono.map { "- \($0)" }.joined(separator: "\n")
        let screens = state.telas.map { "- \($0)" }.joined(separator: "\n")
        return """
        # Manter Ativo

        Atualizado: \(when)
        Versão: \(state.versao)

        \(state.frase)

        - Vigília: \(state.vigiliaConhecida ? state.vigilia : "lendo")
        - CPU: \(cpu) · Super \(superCPU) · Performance \(perfCPU) · carga \(PTFormat.decimal(state.carga))
        - Memória: \(PTFormat.bytes(state.memoriaUsada)) usada · \(PTFormat.bytes(state.memoriaLivre)) livre · compressor \(PTFormat.bytes(state.compressor)) · pressão \(state.pressao)
        - Swap: \(PTFormat.bytes(state.swapUsado)) de \(PTFormat.bytes(state.swapTotal)) · \(state.swapCriptografado ? "criptografado" : "sem cripto")
        - Bateria: \(battery) · \(hold) · \(state.ciclos.map(String.init) ?? "—") ciclos · saúde \(state.saude.map { PTFormat.percent($0 * 100) } ?? "—")
        - Adaptador: \(state.adaptadorWatts.map { "\($0) W" } ?? "—") · máquina \(state.cargaSistema ?? "—")
        - Térmico: \(state.termico)
        - Disco livre: \(disk)
        - Perfil sugerido: \(state.perfilSugerido ?? "nenhum")
        - Spotlight: \(state.spotlight.map { $0 ? "indexando" : "pausado" } ?? "sem leitura")

        ## Telas
        \(screens.isEmpty ? "- nenhuma" : screens)

        ## Quem pesa
        \(families.isEmpty ? "- lendo" : families)

        ## Agentes repetidos
        \(duplicates.isEmpty ? "- nenhum" : duplicates)

        ## Agentes
        \(liveAgents.isEmpty ? "- nenhum" : liveAgents)

        ## Segurando o sono
        \(holders.isEmpty ? "- nenhum" : holders)

        ## USB
        \(state.usb.isEmpty ? "- nenhum" : state.usb.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
