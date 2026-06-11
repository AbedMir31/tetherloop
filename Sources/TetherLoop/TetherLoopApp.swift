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
            Image(systemName: model.status.symbolName)
                .help(model.status.displayName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(width: 660, height: 560)
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
