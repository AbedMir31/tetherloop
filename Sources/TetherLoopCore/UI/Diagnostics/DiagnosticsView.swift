import SwiftUI

public struct DiagnosticsView: View {
    @ObservedObject private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Local Logs", subtitle: "Stored only on this Mac. No telemetry, passwords, or terminal contents.")
            if model.diagnostics.isEmpty {
                ContentUnavailableView("No logs yet", systemImage: "list.bullet.rectangle")
            } else {
                List(model.diagnostics.reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(event.kind.rawValue)
                                .font(.caption.bold())
                            Spacer()
                            Text(event.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(event.message)
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
    }
}
