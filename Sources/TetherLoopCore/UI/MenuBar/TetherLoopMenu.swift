import AppKit
import SwiftUI

public struct TetherLoopMenu: View {
    @ObservedObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Label(model.status.displayName, systemImage: model.status.symbolName)
            .disabled(true)
        Text(model.setupSummary)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        if !model.settings.isSetupVerified {
            Button("Start Setup...", systemImage: "wand.and.stars") {
                showWindow(id: "onboarding")
            }

            Divider()
        }

        Button("Protect Now", systemImage: "shield") {
            model.protectNow()
        }
        .disabled(!model.settings.isSetupVerified)

        Button("Pause Protection", systemImage: "pause.circle") {
            model.pauseProtection()
        }
        Button("Try Hotspot Now", systemImage: "antenna.radiowaves.left.and.right") {
            model.tryHotspotNow()
        }
        Button("Return to Wi-Fi", systemImage: "wifi") {
            Task { await model.returnToWiFi() }
        }

        Divider()

        Button("Setup...", systemImage: "wand.and.stars") {
            showWindow(id: "onboarding")
        }
        Button("Settings...", systemImage: "gearshape") {
            openSettings()
            activateApp()
        }
        Button("View Logs...", systemImage: "list.bullet.rectangle") {
            showWindow(id: "logs")
        }

        Divider()

        Button("Quit TetherLoop", systemImage: "power") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func showWindow(id: String) {
        openWindow(id: id)
        activateApp()
    }

    private func activateApp() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
