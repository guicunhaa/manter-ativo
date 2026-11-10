import Foundation
import Observation
import ManterAtivoCore

struct PendingPrompt: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var message: String
    var confirm: String
    var kind: Kind

    enum Kind: Equatable {
        case wake(WakeMode)
        case killFamily(String)
        case trim(String)
        case delete(String)
        case spotlight(Bool)
        case energy(EnergyChoice)
        case womp(Bool)
        case profile(DeskProfile)
        case installHelper
    }
}

@MainActor
@Observable
final class AppModel {
    var cpu = CPUSample.empty
    var memory = MemorySample.empty
    var battery: BatterySample?
    var thermal = ThermalLevel.nominal
    var families: [AppFamily] = []
    var duplicates: [DuplicateSet] = []
    var bar: AgentBar.Snapshot = .empty
    var inspectedAgentID: String?
    var requestedSection: CockpitSection?
    var holders: [SleepHolder] = []
    var displays: [DisplayInfo] = []
    var usb: [USBDeviceInfo] = []
    var wake = WakeObservation.unknown
    var spotlight: Bool?
    var reclaim: [ReclaimItem] = []
    var diskFreeBytes: Int64?
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var swapHistory: [Double] = []
    var storedHistory: [HistoryPoint] = []
    var statusMessage = "Lendo a máquina…"
    var busy = false
    var reclaimScanning = false
    var pending: PendingPrompt?

    private var started = false
    var wakeKnown = false
    private var lastHistoryWrite = Date.distantPast
    private var lastStateWrite = Date.distantPast
    private var wroteState = false
    private let history = HistoryStore.defaultStore()
    private let hostSampler = HostSampler()

    let releaseVersion: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Desenvolvimento"
        let channel = info["ManterAtivoReleaseChannel"] as? String
        return [version, channel].compactMap { $0 }.joined(separator: " ")
    }()

    var phrase: String {
        PhraseBuilder.make(
            PhraseInput(
                memory: memory,
                topFamilyName: topUserFamily?.name,
                topFamilyBytes: topUserFamily?.residentBytes ?? 0,
                spotlightCPU: families.first { $0.name == "Spotlight" }?.cpuPercent,
                afterEffectsCacheBytes: reclaim.first { $0.id == "after-effects" }?.bytes,
                battery: battery,
                displayCount: displays.count,
                wake: wake.mode,
                wakeKnown: wakeKnown
            )
        )
    }

    var totalAgentBytes: Double {
        bar.rows.reduce(0) { $0 + Double($1.residentBytes) }
    }

    var topUserFamily: AppFamily? {
        families.first { $0.userKillable }
    }

    var menuCPU: String {
        guard let value = cpu.totalPercent else { return "…" }
        return PTFormat.percent(value)
    }

    var wakeSymbol: String {
        guard wakeKnown else { return "circle.dotted" }
        switch wake.mode {
        case .off: return "moon"
        case .screen: return "sun.max"
        case .machine: return "bolt.fill"
        }
    }

    var suggestedProfile: DeskProfile? {
        let external = displays.filter { !$0.isBuiltin }.count
        if battery?.externalConnected == true, external >= 1 { return .mesa }
        if battery?.externalConnected == false, external == 0 { return .bolso }
        return nil
    }

    func start() {
        guard !started else { return }
        started = true
        storedHistory = history.load()
        let sampler = hostSampler
        Task.detached {
            while !Task.isCancelled {
                let reading = await sampler.take()
                await self.ingest(reading)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        Task.detached {
            let census = ProcessCensus()
            while !Task.isCancelled {
                let result = await census.sample()
                await self.applyCensus(result)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        Task.detached {
            while !Task.isCancelled {
                let holders = DeskReaders.holders()
                let wake = WakeController.observe()
                await self.applyPower(holders: holders, wake: wake)
                try? await Task.sleep(for: .seconds(4))
            }
        }
        Task.detached {
            while !Task.isCancelled {
                let usb = DeskReaders.usb()
                let spotlight = DeskReaders.spotlight()
                await self.applyDesk(usb: usb, spotlight: spotlight)
                try? await Task.sleep(for: .seconds(8))
            }
        }
        Task {
            while !Task.isCancelled {
                displays = DeskReaders.displays()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func askWake(_ mode: WakeMode) {
        guard mode != wake.mode else { return }
        pending = PendingPrompt(
            title: "Vigília \(mode.title)",
            message: mode.detail,
            confirm: "Aplicar",
            kind: .wake(mode)
        )
    }

    func askProfile(_ profile: DeskProfile) {
        pending = PendingPrompt(
            title: "Perfil \(profile.title)",
            message: profile == .mesa
                ? "Ativa a vigília de máquina, inclusive com a tampa fechada."
                : "Desliga a vigília. Na bateria, o Mac volta a poder dormir.",
            confirm: "Aplicar",
            kind: .profile(profile)
        )
    }

    func inspectAgent(_ id: String) {
        inspectedAgentID = id
        requestedSection = .agentes
    }

    func selectAgent(_ id: String) {
        inspectedAgentID = id
    }

    func askKill(_ family: AppFamily) {
        guard family.userKillable else { return }
        pending = PendingPrompt(
            title: "Encerrar \(family.name)",
            message: "O app recebe um pedido de término. Trabalho não salvo pode se perder.",
            confirm: "Encerrar",
            kind: .killFamily(family.id)
        )
    }

    func askTrim(_ set: DuplicateSet) {
        pending = PendingPrompt(
            title: "Cópias de \(set.title)",
            message: "Fica o processo \(set.keepPID). As outras \(set.extraPIDs.count) cópias recebem término.",
            confirm: "Encerrar cópias",
            kind: .trim(set.id)
        )
    }

    func askDelete(_ item: ReclaimItem) {
        guard item.exists, item.bytes > 0 else { return }
        pending = PendingPrompt(
            title: "Apagar \(item.title)",
            message: "\(PTFormat.bytes(item.bytes)). \(item.detail) Isso não vai para o Lixo: o espaço precisa voltar agora.",
            confirm: "Apagar e liberar",
            kind: .delete(item.id)
        )
    }

    func askSpotlight(_ enabled: Bool) {
        pending = PendingPrompt(
            title: enabled ? "Retomar Spotlight" : "Pausar Spotlight",
            message: enabled
                ? "A indexação volta. A busca fica atualizada de novo."
                : "A busca deixa de atualizar até você ligar de novo. Alivia CPU no meio de um render.",
            confirm: enabled ? "Retomar" : "Pausar",
            kind: .spotlight(enabled)
        )
    }

    func askEnergy(_ choice: EnergyChoice) {
        pending = PendingPrompt(
            title: choice.title,
            message: "O macOS pede a senha. O modo vale para a máquina inteira.",
            confirm: "Aplicar",
            kind: .energy(choice)
        )
    }

    func askWakeOnLAN(_ enabled: Bool) {
        pending = PendingPrompt(
            title: enabled ? "Ligar Wake on LAN" : "Desligar Wake on LAN",
            message: "A rede deixa ou não de acordar o Mac. Pede senha.",
            confirm: "Aplicar",
            kind: .womp(enabled)
        )
    }

    func askInstallHelper() {
        pending = PendingPrompt(
            title: "Instalar componente",
            message: "Instala o helper de energia uma vez, com senha. É o mesmo componente do Manter Ativo.",
            confirm: "Instalar",
            kind: .installHelper
        )
    }

    func perform(_ prompt: PendingPrompt) async {
        busy = true
        defer { busy = false }
        let helpers = Bundle.main.resourceURL?.appendingPathComponent("helpers", isDirectory: true)
        switch prompt.kind {
        case .wake(let mode):
            statusMessage = "Aplicando vigília…"
            guard let helpers else {
                statusMessage = "Recursos do app não encontrados."
                return
            }
            statusMessage = await Task.detached { WakeController.apply(mode, helpers: helpers) }.value
            wake = await Task.detached { WakeController.observe() }.value
        case .profile(let profile):
            let mode: WakeMode = profile == .mesa ? .machine : .off
            guard let helpers else {
                statusMessage = "Recursos do app não encontrados."
                return
            }
            statusMessage = await Task.detached { WakeController.apply(mode, helpers: helpers) }.value
            wake = await Task.detached { WakeController.observe() }.value
        case .killFamily(let id):
            guard let family = families.first(where: { $0.id == id }) else { return }
            statusMessage = await Task.detached { ActionService.terminate(family: family) }.value
        case .trim(let id):
            guard let set = duplicates.first(where: { $0.id == id }) else { return }
            statusMessage = await Task.detached { ActionService.trim(set: set) }.value
        case .delete(let id):
            statusMessage = "Apagando…"
            statusMessage = await Task.detached { ActionService.delete(categoryID: id) }.value
            await scanReclaim()
        case .spotlight(let enabled):
            statusMessage = await Task.detached { ActionService.spotlight(enabled: enabled) }.value
            spotlight = await Task.detached { DeskReaders.spotlight() }.value
        case .energy(let choice):
            statusMessage = await Task.detached { ActionService.energy(choice) }.value
        case .womp(let enabled):
            statusMessage = await Task.detached { ActionService.wakeOnLAN(enabled) }.value
            wake = await Task.detached { WakeController.observe() }.value
        case .installHelper:
            guard let helpers else {
                statusMessage = "Recursos do app não encontrados."
                return
            }
            let user = NSUserName()
            statusMessage = await Task.detached { WakeController.installHelper(helpers: helpers, user: user) }.value
            wake = await Task.detached { WakeController.observe() }.value
        }
    }

    func scanReclaim() async {
        reclaimScanning = true
        defer { reclaimScanning = false }
        let home = FileManager.default.homeDirectoryForCurrentUser
        reclaim = await Task.detached { ReclaimMeasure.measure(home: home) }.value
        if diskFreeBytes == nil {
            diskFreeBytes = ReclaimMeasure.importantFreeBytes()
        }
    }

    private func ingest(_ reading: HostReading) {
        cpu = reading.cpu
        memory = reading.memory
        battery = reading.battery
        thermal = reading.thermal
        if let free = reading.diskFreeBytes {
            diskFreeBytes = free
        }
        if let total = reading.cpu.totalPercent {
            push(&cpuHistory, total)
        }
        if reading.memory.physicalBytes > 0 {
            let ratio = Double(reading.memory.usedBytes) / Double(reading.memory.physicalBytes) * 100
            push(&memoryHistory, ratio)
        }
        push(&swapHistory, reading.memory.swapRatio * 100)
        if statusMessage == "Lendo a máquina…" {
            statusMessage = "Ao vivo."
        }
        let now = Date()
        if now.timeIntervalSince(lastHistoryWrite) >= 60 {
            lastHistoryWrite = now
            let point = HistoryPoint(
                t: now.timeIntervalSince1970,
                cpu: reading.cpu.totalPercent ?? 0,
                swap: reading.memory.swapRatio,
                memUsed: reading.memory.physicalBytes > 0
                    ? Double(reading.memory.usedBytes) / Double(reading.memory.physicalBytes)
                    : 0,
                batt: reading.battery?.percent
            )
            let store = history
            Task.detached { store.append(point) }
            storedHistory.append(point)
        }
        publishState()
    }

    private func applyCensus(_ result: GroupedProcesses) {
        families = result.families
        duplicates = result.duplicates
        bar = AgentBar.snapshot(result)
        if let inspectedAgentID, bar.rows.contains(where: { $0.id == inspectedAgentID }) == false {
            self.inspectedAgentID = bar.rows.first?.id
        }
        publishState()
    }

    private func applyPower(holders: [SleepHolder], wake: WakeObservation) {
        self.holders = holders
        self.wake = wake
        self.wakeKnown = true
        publishState()
    }

    private func applyDesk(usb: [USBDeviceInfo], spotlight: Bool?) {
        self.usb = usb
        self.spotlight = spotlight
        publishState()
    }

    private func publishState() {
        let now = Date()
        if wroteState, now.timeIntervalSince(lastStateWrite) < 5 { return }
        wroteState = true
        lastStateWrite = now
        let snapshot = deskState(at: now)
        Task.detached { DeskStateStore.write(snapshot) }
    }

    private func deskState(at now: Date) -> DeskState {
        DeskState(
            atualizado: now,
            frase: phrase,
            vigilia: wake.mode.title,
            vigiliaConhecida: wakeKnown,
            cpuTotal: cpu.totalPercent,
            cpuSuper: cpu.superPercent,
            cpuPerformance: cpu.performancePercent,
            carga: cpu.loadAverage,
            memoriaUsada: memory.usedBytes,
            memoriaLivre: memory.freeBytes,
            compressor: memory.compressorBytes,
            pressao: memory.pressure.title,
            swapUsado: memory.swapUsedBytes,
            swapTotal: memory.swapTotalBytes,
            swapCriptografado: memory.swapEncrypted,
            bateriaPercent: battery?.percent,
            ciclos: battery?.cycleCount,
            saude: battery?.healthRatio,
            cargaSegurada: battery?.isSoftwareHold,
            adaptadorWatts: battery?.adapterWatts,
            cargaSistema: battery?.systemLoadMilliWatts.map { PTFormat.watts(fromMilliWatts: $0) },
            termico: thermal.title,
            discoLivre: diskFreeBytes,
            telas: displays.map { display in
                let hz = display.refreshHz > 1 ? "\(Int(display.refreshHz.rounded())) Hz" : "Hz —"
                let kind = display.isBuiltin ? "interna" : "externa"
                return "\(display.name) \(display.pixelWidth)×\(display.pixelHeight) \(hz) \(kind)"
            },
            usb: usb.map(\.name),
            segurandoSono: holders.map { holder in
                guard !holder.detail.contains("/") else { return holder.title }
                return holder.detail.isEmpty ? holder.title : "\(holder.title): \(holder.detail)"
            },
            familias: families.prefix(12).map { family in
                DeskFamily(
                    nome: family.name,
                    ram: family.residentBytes,
                    cpu: family.cpuPercent,
                    processos: family.processCount,
                    podeEncerrar: family.userKillable
                )
            },
            agentesRepetidos: duplicates.map { set in
                DeskDuplicate(titulo: set.title, copias: set.count, ram: set.residentBytes)
            },
            agentes: bar.rows.map { row in
                DeskAgent(titulo: row.title, cpu: row.cpuPercent, ram: row.residentBytes, copias: row.copyCount)
            },
            perfilSugerido: suggestedProfile?.title,
            spotlight: spotlight,
            versao: releaseVersion
        )
    }

    private func push(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > 180 { series.removeFirst(series.count - 180) }
    }
}
