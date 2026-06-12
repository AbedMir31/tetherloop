import SwiftUI

public struct OnboardingView: View {
    @ObservedObject private var model: AppModel
    @State private var isConfirmingTest = false

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("TetherLoop")
                        .font(.largeTitle.bold())
                    Text("Keep long-running AI jobs online when your Mac leaves Wi-Fi.")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if model.needsLocationPermission {
                HStack(spacing: 10) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Location access needed").font(.headline)
                        Text("macOS hides Wi-Fi network names from apps without Location access. TetherLoop only reads the network name; it never tracks location.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Grant Access") { model.requestLocationPermission() }
                }
                .padding(12)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(alignment: .top, spacing: 18) {
                setupCard(
                    step: "1",
                    title: "Trusted Wi-Fi",
                    subtitle: "Add the networks that should trigger failover when they disconnect."
                ) {
                    TrustedNetworksEditor(model: model)
                }

                setupCard(
                    step: "2",
                    title: "Hotspot target",
                    subtitle: "Use a hotspot already remembered by macOS. TetherLoop stores no passwords."
                ) {
                    HotspotEditor(model: model)
                }
            }

            HStack(alignment: .top, spacing: 18) {
                setupCard(
                    step: "3",
                    title: "Test failover",
                    subtitle: "Run a user-initiated test before protection can be enabled."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Button("Run Verification Test", systemImage: "checkmark.seal") {
                            isConfirmingTest = true
                        }
                        .disabled(model.settings.hotspotSSID == nil)
                        Text(model.settings.isSetupVerified ? "Protection is verified." : "Run a real hotspot test before relying on protection.")
                            .font(.caption)
                            .foregroundStyle(model.settings.isSetupVerified ? .green : .secondary)
                    }
                }

                setupCard(
                    step: "4",
                    title: "Protection",
                    subtitle: "Enable the protection loop and optional standard idle-sleep prevention."
                ) {
                    ProtectionToggles(model: model)
                }
            }

            Spacer()
        }
        .padding(28)
        .confirmationDialog(
            "Test failover to \(model.settings.hotspotSSID ?? "your hotspot")?",
            isPresented: $isConfirmingTest
        ) {
            Button("Switch and Test") {
                Task { await model.runSetupVerificationTest() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your Mac will briefly leave the current Wi-Fi network and join the hotspot. Active downloads or calls may be interrupted. TetherLoop offers to return to your Wi-Fi afterwards.")
        }
        .alert(
            "Verification succeeded",
            isPresented: Binding(
                get: { model.postVerificationReturn != nil },
                set: { if !$0 { model.dismissPostVerificationReturn() } }
            )
        ) {
            if case .offered = model.postVerificationReturn {
                Button("Return to Wi-Fi") { Task { await model.acceptPostVerificationReturn() } }
                Button("Stay on Hotspot", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            if case .offered(let ssid) = model.postVerificationReturn {
                Text("Your hotspot works. Return to \(ssid) now?")
            } else {
                Text("Your hotspot works. You were not on Wi-Fi before the test, so TetherLoop stayed on the hotspot. Use Return to Wi-Fi in the menu when ready.")
            }
        }
    }

    private func setupCard<Content: View>(
        step: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(step)
                    .font(.headline)
                    .frame(width: 28, height: 28)
                    .background(.blue.opacity(0.14), in: Circle())
                SectionHeader(title, subtitle: subtitle)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }
}
