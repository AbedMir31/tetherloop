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

    private var availableChoices: [String] {
        model.selectableSSIDs.filter { !model.settings.trustedSSIDs.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NetworkSelectionPicker(
                model: model,
                title: "Add trusted Wi-Fi",
                placeholder: availableChoices.isEmpty ? "No remembered networks found" : "Choose Wi-Fi network",
                choices: availableChoices,
                selection: Binding(
                    get: { "" },
                    set: { ssid in
                        guard !ssid.isEmpty else { return }
                        model.addTrustedSSID(ssid)
                    }
                )
            )

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

            if let error = model.networkChoicesError {
                Text("Could not load remembered networks: \(error)")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .task {
            await model.refreshNetworkChoices()
        }
    }
}

struct HotspotEditor: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NetworkSelectionPicker(
                model: model,
                title: "Hotspot target",
                placeholder: model.selectableSSIDs.isEmpty ? "No remembered networks found" : "Choose hotspot",
                choices: model.selectableSSIDs,
                selection: Binding(
                    get: { model.settings.hotspotSSID ?? "" },
                    set: { ssid in
                        guard !ssid.isEmpty else { return }
                        model.setHotspotSSID(ssid)
                    }
                )
            )
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
        .task {
            await model.refreshNetworkChoices()
        }
    }
}

private struct NetworkSelectionPicker: View {
    @ObservedObject var model: AppModel
    let title: String
    let placeholder: String
    let choices: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 8) {
            Picker(title, selection: $selection) {
                Text(placeholder)
                    .tag("")
                    .selectionDisabled(true)
                ForEach(choices, id: \.self) { ssid in
                    Label(ssid, systemImage: "wifi")
                        .tag(ssid)
                }
            }
            .pickerStyle(.menu)
            .disabled(choices.isEmpty && selection.isEmpty)

            Button("Refresh networks", systemImage: "arrow.clockwise") {
                Task { await model.refreshNetworkChoices() }
            }
            .labelStyle(.iconOnly)
            .help("Refresh remembered Wi-Fi networks")

            if model.isRefreshingNetworks {
                ProgressView()
                    .controlSize(.small)
            }
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
