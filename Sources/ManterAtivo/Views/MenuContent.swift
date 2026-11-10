import AppKit
import SwiftUI
import ManterAtivoCore

struct MenuLabel: View {
    var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.wakeSymbol)
            Text(model.menuCPU)
                .monospacedDigit()
        }
        .onAppear { model.start() }
    }
}

struct MenuContent: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Abrir painel") { openCockpit() }
        Button(MenuTitle.short(model.wakeKnown ? "Vigília: \(model.wake.mode.title)" : "Vigília: lendo…")) {}
            .disabled(true)
        Divider()
        let top = Array(model.families.filter(\.userKillable).prefix(3))
        if top.isEmpty {
            Button("Lendo processos") {}
                .disabled(true)
        } else {
            ForEach(top) { family in
                Button(MenuTitle.short("Encerrar \(family.name)")) {
                    model.askKill(family)
                    openCockpit()
                }
            }
        }
        Divider()
        Button("Medir espaço") {
            openCockpit()
            Task { await model.scanReclaim() }
        }
        SettingsLink { Text("Ajustes") }
        Divider()
        Button("Sair (vigília fica)") {
            NSApp.terminate(nil)
        }
    }

    private func openCockpit() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "cockpit")
    }
}
