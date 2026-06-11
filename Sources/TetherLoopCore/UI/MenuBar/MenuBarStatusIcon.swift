import SwiftUI

public struct MenuBarStatusIcon: View {
    private let status: ProtectionStatus

    public init(status: ProtectionStatus) {
        self.status = status
    }

    public var body: some View {
        ZStack {
            border

            Image(systemName: "link")
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .scaleEffect(status == .failed ? 0.9 : 1)
        }
        .frame(width: 22, height: 18)
        .foregroundStyle(.primary)
        .help(status.displayName)
    }

    @ViewBuilder
    private var border: some View {
        switch status {
        case .unconfigured:
            EmptyView()
        case .monitoring:
            Circle()
                .stroke(lineWidth: 1.4)
                .frame(width: 17, height: 17)
        case .protected, .onHotspot:
            Image(systemName: "shield")
                .font(.system(size: 17, weight: .medium))
                .symbolRenderingMode(.monochrome)
        case .paused:
            RoundedRectangle(cornerRadius: 4)
                .stroke(style: StrokeStyle(lineWidth: 1.4, dash: [2, 2]))
                .frame(width: 18, height: 16)
        case .switching:
            Circle()
                .trim(from: 0.1, to: 0.86)
                .stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-45))
                .frame(width: 17, height: 17)
        case .failed:
            Triangle()
                .stroke(lineWidth: 1.3)
                .frame(width: 18, height: 16)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
