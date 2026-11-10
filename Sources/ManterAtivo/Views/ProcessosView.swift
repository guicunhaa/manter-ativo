import SwiftUI
import ManterAtivoCore

struct ProcessosView: View {
    var model: AppModel
    @State private var query = ""

    private var families: [AppFamily] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.families }
        return model.families.filter { $0.name.localizedStandardContains(text) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Famílias somam os processos-filho. Encerrar pede confirmação e não mexe em WindowServer, na vigília nem no harness do mouse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !model.duplicates.isEmpty {
                    GlassGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agentes repetidos")
                            .font(.headline)
                        ForEach(model.duplicates) { set in
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(set.title)
                                    Text("\(set.count) cópias · \(PTFormat.bytes(set.residentBytes)) · fica o \(set.keepPID)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Encerrar cópias") { model.askTrim(set) }
                                    .disabled(model.busy)
                            }
                            .padding(12)
                            .glassCard(corner: 12)
                        }
                    }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quem pesa")
                        .font(.headline)
                    ForEach(families) { family in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(family.name)
                                Text("\(PTFormat.bytes(family.residentBytes)) · \(PTFormat.percent(family.cpuPercent)) · \(family.processCount) processos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            if family.userKillable {
                                Button("Encerrar") { model.askKill(family) }
                                    .disabled(model.busy)
                            } else {
                                Text("sistema")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider()
                    }
                }
            }
            .padding(20)
        }
        .searchable(text: $query, prompt: "Buscar app")
    }
}
