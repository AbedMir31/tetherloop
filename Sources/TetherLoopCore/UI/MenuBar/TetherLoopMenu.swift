import SwiftUI

public struct TetherLoopMenu: View {
    @ObservedObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusBadge(status: model.status)
            Text(model.setupSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Protect Now", systemImage: "shield") {
                model.protectNow()
            }
            Button("Pause Protection", systemImage: "pause.circle") {
                model.pauseProtection()
            }
            Button("Try Hotspot Now", systemImage: "antenna.radiowaves.left.and.right") {
                model.tryHotspotNow()
            }
            Button("Return to Wi-Fi", systemImage: "wifi") {
                model.returnToWiFi()
            }

            Divider()

            Button("Setup", systemImage: "wand.and.stars") {
                openWindow(id: "onboarding")
            }
            Button("Settings", systemImage: "gearshape") {
                openSettings()
            }
            Button("View Logs", systemImage: "list.bullet.rectangle") {
                openWindow(id: "logs")
            }

            Divider()

            Button("Quit TetherLoop", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 6)
        .frame(minWidth: 260)
        .task {
            await model.pollNetwork()
        }
    }
}
