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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(model.bar.openPanelTitle) { openCockpit(inspect: nil) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Spacer(minLength: 8)
                Label(model.wakeKnown ? model.wake.mode.title : "Lendo", systemImage: model.wakeSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(model.bar.sectionTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if model.bar.rows.isEmpty {
                Text("Nenhum agente agora")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .panelSurface(corner: 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.bar.rows) { row in
                            Button {
                                openCockpit(inspect: row.id)
                            } label: {
                                AgentMeasureRow(row: row, selected: model.inspectedAgentID == row.id, compact: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            let choices = model.families.filter(\.userKillable).prefix(3)
            if !choices.isEmpty {
                DisclosureGroup("Encerrar um app") {
                    ForEach(choices) { family in
                        Button("Encerrar " + family.name) {
                            model.askKill(family)
                            openCockpit(inspect: nil)
                        }
                        .controlSize(.small)
                    }
                }
            }
            Divider()
            HStack(spacing: 8) {
                Button("Medir espaço") {
                    model.requestedSection = .espaco
                    openCockpit(inspect: nil)
                    Task { await model.scanReclaim() }
                }
                .controlSize(.small)
                .disabled(model.reclaimScanning || model.busy)
                Spacer(minLength: 8)
                SettingsLink {
                    Text(MenuTitle.short("Ajustes"))
                }
            }

            Button(model.bar.quitTitle) {
                NSApp.terminate(nil)
            }
            .controlSize(.small)

        }
        .padding(12)
        .frame(width: 326)
    }

    private func openCockpit(inspect id: String?) {
        if let id {
            model.inspectAgent(id)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "cockpit")
    }
}
