import SwiftUI
import ManterAtivoCore

struct EspacoView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.diskFreeBytes.map { "Livres agora: \(PTFormat.bytes(Int64($0)))" } ?? "Livres agora: medindo")
                            .font(.title3.weight(.semibold))
                        Text("Cada linha só apaga a pasta dela, depois da confirmação. Cache recria. Projeto, Mail, Fotos e Application Support ficam fora.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(model.reclaimScanning ? "Medindo…" : "Medir") {
                        Task { await model.scanReclaim() }
                    }
                    .disabled(model.reclaimScanning || model.busy)
                }
                if model.reclaim.isEmpty {
                    ContentUnavailableView(
                        "Nada medido ainda",
                        systemImage: "internaldrive",
                        description: Text("A medição lê o tamanho. Não apaga nada.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(model.reclaim) { item in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                Text(item.exists ? item.detail : "Pasta ausente.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.exists ? PTFormat.bytes(item.bytes) : "—")
                                .font(.body.monospacedDigit().weight(.semibold))
                            Button("Apagar") { model.askDelete(item) }
                                .disabled(!item.exists || item.bytes == 0 || model.busy)
                        }
                        .padding(12)
                        .panelSurface(corner: 12)
                    }
                }
            }
            .padding(20)
        }
    }
}
