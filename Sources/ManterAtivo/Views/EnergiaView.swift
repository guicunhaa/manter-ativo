import SwiftUI
import ManterAtivoCore

struct EnergiaView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let battery = model.battery {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(battery.percent)% · \(battery.condition)")
                            .font(.title2.weight(.semibold))
                        Text("Fábrica \(PTFormat.mAh(battery.designmAh)) · cheia hoje \(PTFormat.mAh(battery.fullmAh)) · agora \(PTFormat.mAh(battery.currentmAh))")
                            .font(.body.monospacedDigit())
                        Text("\(battery.cycleCount) ciclos · \(battery.voltageMilliVolts) mV · \(battery.amperageMilliAmps) mA")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if let name = battery.adapterName, battery.externalConnected {
                            Text("\(name) · \(battery.adapterWatts.map { "\($0) W" } ?? "watts —") · máquina \(battery.systemLoadMilliWatts.map { PTFormat.watts(fromMilliWatts: $0) } ?? "—")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(batteryExplain(battery))
                            .font(.callout)
                            .padding(.top, 4)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panelSurface()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label("Pressão térmica", systemImage: "thermometer.medium")
                        .font(.headline)
                    Text(model.cpu.totalPercent == nil ? "Aguardando leitura" : model.thermal.title)
                        .font(.title2.weight(.medium))
                    Text("Modo de energia · " + energyMode)
                        .foregroundStyle(.secondary)
                    HStack {
                        ForEach([EnergyChoice.automatic, .low, .high], id: \.self) { choice in
                            Button(choice.title) { model.askEnergy(choice) }
                                .disabled(model.busy)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .panelSurface()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Histórico de CPU")
                        .font(.headline)
                    Text(historyLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Sparkline(samples: model.storedHistory.suffix(240).map(\.cpu))
                        .stroke(.orange, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(height: 48)
                    Text("CPU das amostras guardadas. Uma linha por minuto, por 7 dias.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .panelSurface()
                spotlightRow
            }
            .padding(20)
        }
    }

    private var energyMode: String {
        switch model.wake.flags.powermode {
        case 0: "Automático"
        case 1: "Baixa energia"
        case 2: "Alta potência"
        default: "Sem leitura"
        }
    }

    private var spotlightRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spotlight")
                Text(spotlightText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.spotlight == true {
                Button("Pausar") { model.askSpotlight(false) }
            } else if model.spotlight == false {
                Button("Retomar") { model.askSpotlight(true) }
            }
        }
        .disabled(model.busy)
        .padding(12)
        .panelSurface(corner: 12)
    }

    private var spotlightText: String {
        switch model.spotlight {
        case true: "Indexando. Se estiver em pico, pausar alivia."
        case false: "Pausado. A busca fica desatualizada."
        case nil: "Sem leitura ainda."
        }
    }

    private var historyLine: String {
        if model.storedHistory.isEmpty {
            return "O histórico de 7 dias começa nesta execução. A primeira amostra entra em um minuto."
        }
        return "\(model.storedHistory.count) amostras guardadas neste Mac."
    }

    private func batteryExplain(_ battery: BatterySample) -> String {
        if battery.isSoftwareHold {
            return "O carregador está ligado e a corrente está em zero. O macOS segurou a carga. Não é adaptador fraco."
        }
        if battery.thermallyLimited {
            return "A carga está limitada por calor."
        }
        if battery.isCharging {
            return "A bateria está recebendo carga."
        }
        if !battery.externalConnected {
            return "Rodando na bateria."
        }
        return battery.condition
    }
}
