import SwiftUI

public struct SettingsView: View {
    @ObservedObject private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            Form {
                SectionHeader("Protection", subtitle: "Configure Free V1 behavior.")
                ProtectionToggles(model: model)
                Toggle("Global failover", isOn: Binding(
                    get: { model.settings.isGlobalFailoverEnabled },
                    set: { model.setGlobalFailoverEnabled($0) }
                ))
                Text("Global failover can use cellular data unexpectedly. Trusted networks only remains the safer default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .tabItem {
                Label("Protection", systemImage: "shield")
            }

            Form {
                SectionHeader("Networks", subtitle: "TetherLoop stores SSIDs only. Hotspot passwords stay with macOS.")
                TrustedNetworksEditor(model: model)
                Divider()
                HotspotEditor(model: model)
            }
            .padding(20)
            .tabItem {
                Label("Networks", systemImage: "wifi")
            }

            DiagnosticsView(model: model)
                .tabItem {
                    Label("Logs", systemImage: "list.bullet.rectangle")
                }
        }
    }
}

struct TrustedNetworksEditor: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Home Wi-Fi", text: $model.draftTrustedSSID)
                    .textFieldStyle(.roundedBorder)
                Button("Add") {
                    model.addTrustedSSID(model.draftTrustedSSID)
                }
                .disabled(model.draftTrustedSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.trustedSSIDs.isEmpty {
                Text("No trusted networks yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.trustedSSIDs, id: \.self) { ssid in
                    HStack {
                        Label(ssid, systemImage: "wifi")
                        Spacer()
                        Button("Remove", systemImage: "minus.circle") {
                            model.removeTrustedSSID(ssid)
                        }
                        .labelStyle(.iconOnly)
                    }
                }
            }
        }
    }
}

struct HotspotEditor: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(model.settings.hotspotSSID ?? "iPhone Hotspot", text: $model.draftHotspotSSID)
                    .textFieldStyle(.roundedBorder)
                Button("Set") {
                    model.setHotspotSSID(model.draftHotspotSSID)
                }
                .disabled(model.draftHotspotSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Label(model.settings.hotspotSSID ?? "No hotspot selected", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                if model.settings.isSetupVerified {
                    Label("Verified", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Test required", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
        }
    }
}

struct ProtectionToggles: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enable network protection", isOn: Binding(
                get: { model.settings.isProtectionEnabled },
                set: { model.setProtectionEnabled($0) }
            ))
            .disabled(!model.settings.isSetupVerified)

            Toggle("Prevent idle sleep while protected", isOn: Binding(
                get: { model.settings.isSleepPreventionEnabled },
                set: { model.setSleepPreventionEnabled($0) }
            ))

            Toggle("Launch at login", isOn: Binding(
                get: { model.settings.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            if !model.settings.isSetupVerified {
                Text("Protection is disabled until setup is verified.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
