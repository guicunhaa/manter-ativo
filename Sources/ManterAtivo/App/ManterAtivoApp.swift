import AppKit
import SwiftUI

/// Menu-bar utility. `.accessory` is intentional so the Dock stays clear
/// until the Cockpit window is open. Closing that window returns to the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let opensCockpit = ProcessInfo.processInfo.arguments.contains("--cockpit")
        NSApp.setActivationPolicy(opensCockpit ? .regular : .accessory)
        if opensCockpit {
            NSApp.activate(ignoringOtherApps: true)
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { _ in
            DispatchQueue.main.async {
                let visible = NSApp.windows.contains { $0.isVisible && $0.level == .normal }
                if !visible {
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct ManterAtivoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    private var opensCockpitAtLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("--cockpit")
    }

    var body: some Scene {
        Window("Manter Ativo", id: "cockpit") {
            CockpitView(model: model)
        }
        .defaultLaunchBehavior(opensCockpitAtLaunch ? .presented : .suppressed)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            MenuLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
