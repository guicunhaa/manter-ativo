import SwiftUI
import ManterAtivoCore

struct AgoraView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            GlassGroup {
            VStack(alignment: .leading, spacing: 16) {
                PhraseBanner(text: model.phrase)
                wakeControl
                if let profile = model.suggestedProfile {
                    profileHint(profile)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricCard(
                        title: "CPU",
                        value: model.cpu.totalPercent.map { PTFormat.percent($0) } ?? "—",
                        subtitle: cpuSubtitle,
                        samples: model.cpuHistory,
                        tint: .orange
                    )
                    MetricCard(
                        title: "Memória",
                        value: model.memory.physicalBytes == 0 ? "—" : PTFormat.bytes(model.memory.usedBytes),
                        subtitle: memorySubtitle,
                        samples: model.memoryHistory,
                        tint: .teal
                    )
                    MetricCard(
                        title: "Swap",
                        value: model.memory.swapTotalBytes == 0 ? "—" : PTFormat.bytes(model.memory.swapUsedBytes),
                        subtitle: swapSubtitle,
                        samples: model.swapHistory,
                        tint: model.memory.swapRatio >= 0.75 ? .red : .secondary,
                        alerts: model.memory.swapRatio >= 0.75
                    )
                    MetricCard(
                        title: "Bateria",
                        value: model.battery.map { "\($0.percent)%" } ?? "—",
                        subtitle: batterySubtitle,
                        samples: model.storedHistory.suffix(60).map { Double($0.batt ?? 0) },
                        tint: .green
                    )
                }
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            }
        }
    }

    private var wakeControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vigília")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.wakeKnown {
                Picker("Vigília", selection: Binding(
                    get: { model.wake.mode },
                    set: { model.askWake($0) }
                )) {
                    ForEach(WakeMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
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
                Text(profile == .mesa ? "Isso parece a mesa" : "Isso parece o bolso")
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
        .glassCard()
    }

    private var cpuSubtitle: String {
        let superText = model.cpu.superPercent.map { "Super \(PTFormat.percent($0))" } ?? "Super —"
        let performanceText = model.cpu.performancePercent.map { "Performance \(PTFormat.percent($0))" } ?? "Performance —"
        let load = "carga \(PTFormat.decimal(model.cpu.loadAverage))"
        return "\(superText) · \(performanceText) · \(load)"
    }

    private var memorySubtitle: String {
        let free = PTFormat.bytes(model.memory.freeBytes)
        let compressor = PTFormat.bytes(model.memory.compressorBytes)
        return "livre \(free) · compressor \(compressor) · pressão \(model.memory.pressure.title.lowercased())"
    }

    private var swapSubtitle: String {
        let total = PTFormat.bytes(model.memory.swapTotalBytes)
        let lock = model.memory.swapEncrypted ? "criptografado" : "sem cripto"
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
