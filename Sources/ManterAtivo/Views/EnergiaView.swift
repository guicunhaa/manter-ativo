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
                    .glassCard()
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Calor")
                        .font(.headline)
                    Text("Pressão térmica: \(model.thermal.title).")
                    Text("O SMC deste M5 Pro não entregou RPM da ventoinha para o app. Sem leitura, não há slider. O controle que a Apple abre é o modo de energia.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    ForEach([EnergyChoice.automatic, .low, .high], id: \.self) { choice in
                        Button(choice.title) { model.askEnergy(choice) }
                            .disabled(model.busy)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Histórico")
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
                spotlightRow
            }
            .padding(20)
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
        .glassCard(corner: 12)
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
