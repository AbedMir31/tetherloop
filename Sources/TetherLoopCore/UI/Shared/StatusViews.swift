import SwiftUI

public struct StatusBadge: View {
    private let status: ProtectionStatus

    public init(status: ProtectionStatus) {
        self.status = status
    }

    public var body: some View {
        Label(status.displayName, systemImage: status.symbolName)
            .font(.headline)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

public struct SectionHeader: View {
    private let title: String
    private let subtitle: String?

    public init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
