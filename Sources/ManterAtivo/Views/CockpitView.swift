import SwiftUI

struct CockpitView: View {
    var model: AppModel
    @State private var section: CockpitSection = .agora

    var body: some View {
        NavigationSplitView {
            List(CockpitSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.symbol)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle(section.title)
                .toolbar {
                    ToolbarItem(placement: .status) {
                        HStack(spacing: 6) {
                            Text(model.wakeKnown ? model.wake.mode.title : "Lendo")
                            Text("·")
                            Text(model.menuCPU)
                                .monospacedDigit()
                                .accessibilityLabel("CPU \(model.menuCPU)")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
        }
        .frame(minWidth: 920, minHeight: 620)
        .alert(model.pending?.title ?? "", isPresented: pendingBinding) {
            Button(model.pending?.confirm ?? "Aplicar", role: .destructive) {
                guard let prompt = model.pending else { return }
                model.pending = nil
                Task { await model.perform(prompt) }
            }
            Button("Cancelar", role: .cancel) { model.pending = nil }
        } message: {
            Text(model.pending?.message ?? "")
        }
        .onAppear { model.start() }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .agora: AgoraView(model: model)
        case .processos: ProcessosView(model: model)
        case .espaco: EspacoView(model: model)
        case .mesa: MesaView(model: model)
        case .energia: EnergiaView(model: model)
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { model.pending != nil },
            set: { if !$0 { model.pending = nil } }
        )
    }
}
