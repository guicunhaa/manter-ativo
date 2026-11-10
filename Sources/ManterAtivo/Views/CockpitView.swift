import SwiftUI

struct CockpitView: View {
    var model: AppModel
    @State private var section: CockpitSection = .agora

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                Section("Atividade") {
                    navigationRows([.agora, .agentes, .processos])
                }
                Section("Este Mac") {
                    navigationRows([.espaco, .mesa, .energia])
                }
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Divider().padding(.bottom, 5)
                    Label(model.wakeKnown ? "Vigília · " + model.wake.mode.title : "Lendo vigília…",
                          systemImage: model.wakeSymbol)
                        .font(.subheadline.weight(.medium))
                    Text("CPU " + model.menuCPU)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle("Manter Ativo")
                .navigationSubtitle(section.title)
        }
        .frame(minWidth: 780, minHeight: 550)
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
        .onAppear {
            revealRequestedSection()
        }
        .onChange(of: model.requestedSection) { _, _ in revealRequestedSection() }
    }

    private func navigationRows(_ items: [CockpitSection]) -> some View {
        ForEach(items) { item in
            Label(item.title, systemImage: item.symbol).tag(item)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section {
        case .agora: AgoraView(model: model)
        case .agentes: AgentesView(model: model)
        case .processos: ProcessosView(model: model)
        case .espaco: EspacoView(model: model)
        case .mesa: MesaView(model: model)
        case .energia: EnergiaView(model: model)
        }
    }

    private func revealRequestedSection() {
        guard let target = model.requestedSection else { return }
        section = target
        model.requestedSection = nil
    }

    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { model.pending != nil },
            set: { if !$0 { model.pending = nil } }
        )
    }
}
