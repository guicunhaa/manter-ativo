import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var model: AppModel
    @State private var loginNote = "O app fica na barra. Entrar no login é opcional."

    var body: some View {
        Form {
            Section("Barra de menus") {
                Text("Fechar a janela não solta a vigília. Sair do app também não. A vigília só muda quando você escolhe Desligada, Tela ou Máquina.")
                LabeledContent("Componente de energia") {
                    Text(model.wake.helperInstalled ? "Instalado" : "Ausente")
                }
                if !model.wake.helperInstalled {
                    Button("Instalar componente") { model.askInstallHelper() }
                }
            }
            Section("Abrir ao entrar") {
                Text(loginNote)
                Button("Registrar no login") { registerLogin() }
                Button("Tirar do login") { unregisterLogin() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
        .onAppear { model.start() }
    }

    private func registerLogin() {
        do {
            try SMAppService.mainApp.register()
            loginNote = "Pedido de login enviado. O macOS pode pedir confirmação em Ajustes do Sistema."
        } catch {
            loginNote = error.localizedDescription
        }
    }

    private func unregisterLogin() {
        do {
            try SMAppService.mainApp.unregister()
            loginNote = "Removido da abertura automática."
        } catch {
            loginNote = error.localizedDescription
        }
    }
}
