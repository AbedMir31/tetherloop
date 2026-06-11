import SwiftUI

public struct OnboardingView: View {
    @ObservedObject private var model: AppModel

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
                            Task { await model.runSetupVerificationTest() }
                        }
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
