import SwiftUI
import TetherLoopCore

@main
struct TetherLoopApp: App {
    @NSApplicationDelegateAdaptor(TetherLoopAppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel.live()
        model.startMonitoring()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            TetherLoopMenu(model: model)
        } label: {
            MenuBarStatusIcon(status: model.status)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(width: 560, height: 380)
        }

        Window("TetherLoop Setup", id: "onboarding") {
            OnboardingView(model: model)
                .frame(width: 700, height: 560)
        }

        Window("TetherLoop Logs", id: "logs") {
            DiagnosticsView(model: model)
                .frame(width: 760, height: 520)
        }
    }
}
