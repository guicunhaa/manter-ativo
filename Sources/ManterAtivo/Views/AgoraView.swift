import SwiftUI
import ManterAtivoCore

struct AgoraView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhraseBanner(model: model)
                agentGlance
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 174), spacing: 10, alignment: .top)], spacing: 10) {
                    MetricCard(
                        title: "CPU", symbol: "cpu",
                        value: model.cpu.totalPercent.map { PTFormat.percent($0) } ?? "—",
                        subtitle: cpuSubtitle,
                        samples: model.cpuHistory,
                        tint: .orange
                    )
                    MetricCard(
                        title: "Memória", symbol: "memorychip",
                        value: model.memory.physicalBytes == 0 ? "—" : PTFormat.bytes(model.memory.usedBytes),
                        subtitle: memorySubtitle,
                        samples: model.memoryHistory,
                        tint: .teal
                    )
                    MetricCard(
                        title: "Swap", symbol: "arrow.left.arrow.right",
                        value: model.memory.swapTotalBytes == 0 ? "—" : PTFormat.bytes(model.memory.swapUsedBytes),
                        subtitle: swapSubtitle,
                        samples: model.swapHistory,
                        tint: model.memory.swapRatio >= 0.75 ? .red : .secondary,
                        alerts: model.memory.swapRatio >= 0.75
                    )
                    MetricCard(
                        title: "Bateria", symbol: "battery.75percent",
                        value: model.battery.map { "\($0.percent)%" } ?? "—",
                        subtitle: batterySubtitle,
                        samples: model.storedHistory.suffix(60).compactMap { $0.batt.map(Double.init) },
                        tint: .green
                    )
                }
                wakeControl
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .panelSurface()
                if let profile = model.suggestedProfile {
                    profileHint(profile)
                }
                if !["Ao vivo.", "Lendo a máquina…"].contains(model.statusMessage) {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private var agentGlance: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Agentes locais")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Ver agentes") { model.requestedSection = .agentes }
                    .controlSize(.small)
            }
            if model.bar.rows.isEmpty {
                Text("Nenhum agente local detectado.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                AgentColumnHeadings()
                ForEach(model.bar.rows.prefix(3)) { row in
                    Divider()
                    Button { model.inspectAgent(row.id) } label: {
                        AgentMeasureRow(row: row, selected: model.inspectedAgentID == row.id,
                                        totalAgentBytes: model.totalAgentBytes)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .panelSurface()
    }

    private var wakeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Controle de vigília")
                .font(.headline)
            if model.wakeKnown {
                Picker("Vigília", selection: Binding(
                    get: { model.wake.mode },
                    set: { model.askWake($0) }
                )) {
                    ForEach(WakeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .disabled(model.busy)
                .accessibilityLabel("Vigília")
                Text(model.wake.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !model.wake.helperInstalled {
                    Button("Instalar componente") { model.askInstallHelper() }
                        .disabled(model.busy)
                }
            } else {
                Text("Lendo a vigília…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func profileHint(_ profile: DeskProfile) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Perfil sugerido · " + profile.title)
                    .font(.headline)
                Text(profile == .mesa
                     ? "Tomada e monitor externo. A vigília de máquina combina com esse posto."
                     : "Bateria e uma tela. Dá para soltar a vigília.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(profile.title) { model.askProfile(profile) }
                .disabled(model.busy)
        }
        .padding(14)
        .panelSurface()
    }

    private var cpuSubtitle: String {
        let superText = model.cpu.superPercent.map { "Super \(PTFormat.percent($0))" } ?? "Super —"
        let performanceText = model.cpu.performancePercent.map { "Performance \(PTFormat.percent($0))" } ?? "Performance —"
        let load = "carga \(PTFormat.decimal(model.cpu.loadAverage))"
        return "\(superText) · \(performanceText) · \(load)"
    }

    private var memorySubtitle: String {
        guard model.memory.physicalBytes > 0 else { return "Aguardando leitura" }
        let free = PTFormat.bytes(model.memory.freeBytes)
        let compressor = PTFormat.bytes(model.memory.compressorBytes)
        return "livre \(free) · compressor \(compressor) · pressão \(model.memory.pressure.title.lowercased())"
    }

    private var swapSubtitle: String {
        guard model.memory.physicalBytes > 0 else { return "Aguardando leitura" }
        let total = PTFormat.bytes(model.memory.swapTotalBytes)
        if model.memory.swapRatio >= 0.75 { return "Uso elevado · de " + total }
        let lock = model.memory.swapEncrypted ? "criptografado" : "sem criptografia"
        return "de \(total) · \(lock)"
    }

    private var batterySubtitle: String {
        guard let battery = model.battery else { return "Sem leitura da bateria." }
        let health = battery.healthRatio.map { PTFormat.percent($0 * 100) } ?? "—"
        let hold = battery.isSoftwareHold ? "carga segurada" : (battery.isCharging ? "carregando" : battery.condition)
        let load = battery.systemLoadMilliWatts.map { PTFormat.watts(fromMilliWatts: $0) } ?? ""
        return "saúde \(health) · \(battery.cycleCount) ciclos · \(hold) \(load)"
    }
}
