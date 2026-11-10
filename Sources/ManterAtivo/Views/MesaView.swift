import SwiftUI
import ManterAtivoCore

struct MesaView: View {
    var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    profileButton(.mesa)
                    profileButton(.bolso)
                    Spacer()
                }
                group("Telas") {
                    ForEach(model.displays) { display in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(display.name + (display.isMain ? " · principal" : ""))
                            Text(displayLine(display))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }
                }
                group("Segurando o sono") {
                    ForEach(model.holders) { holder in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(holder.title)
                            Text(holder.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
                group("USB") {
                    ForEach(model.usb) { device in
                        Text(device.name)
                            .padding(.vertical, 2)
                    }
                }
                HStack {
                    Text(model.wakeKnown ? (model.wake.flags.wakeOnLAN ? "Wake on LAN ligado" : "Wake on LAN desligado") : "Lendo Wake on LAN…")
                    Spacer()
                    Button(model.wake.flags.wakeOnLAN ? "Desligar" : "Ligar") {
                        model.askWakeOnLAN(!model.wake.flags.wakeOnLAN)
                    }
                    .disabled(model.busy || !model.wakeKnown)
                }
                .padding(12)
                .panelSurface(corner: 12)
                if model.holders.contains(where: { $0.title == "Microfone" }) {
                    Text("Tem um tap de microfone segurando o sono. Fechar o app que escuta solta isso.")
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .panelSurface(corner: 12)
                }
            }
            .padding(20)
        }
    }

    private func profileButton(_ profile: DeskProfile) -> some View {
        Button(profile.title) { model.askProfile(profile) }
            .buttonStyle(.borderedProminent)
            .tint(profile == .mesa ? .orange : .secondary)
            .disabled(model.busy)
    }

    private func displayLine(_ display: DisplayInfo) -> String {
        let hz = display.refreshHz > 1 ? "\(Int(display.refreshHz.rounded())) Hz" : "Hz —"
        let kind = display.isBuiltin ? "interna" : "externa"
        return "\(display.pixelWidth)×\(display.pixelHeight) · parece \(display.pointWidth)×\(display.pointHeight) · \(hz) · \(kind)"
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .panelSurface()
    }
}
