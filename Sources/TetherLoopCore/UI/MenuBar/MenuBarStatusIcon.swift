import AppKit
import SwiftUI

public struct MenuBarStatusIcon: View {
    private let status: ProtectionStatus

    public init(status: ProtectionStatus) {
        self.status = status
    }

    public var body: some View {
        Image(nsImage: MenuBarStatusImage.make(for: status))
            .renderingMode(.template)
            .help(status.displayName)
    }
}

private enum MenuBarStatusImage {
    static func make(for status: ProtectionStatus) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        NSColor.black.setStroke()
        NSColor.black.setFill()

        drawBorder(for: status, in: NSRect(origin: .zero, size: size))
        drawSymbol("link", pointSize: status == .protected || status == .onHotspot ? 13.5 : 12.5, weight: .bold, in: linkRect(for: status, size: size))

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func drawBorder(for status: ProtectionStatus, in rect: NSRect) {
        switch status {
        case .unconfigured:
            return
        case .monitoring:
            let path = NSBezierPath(ovalIn: NSRect(x: 1.0, y: 1.4, width: 16, height: 16))
            path.lineWidth = 1.4
            path.stroke()
        case .protected, .onHotspot:
            drawShieldOutline(in: NSRect(x: 0.8, y: 0.6, width: 16.4, height: 16.8))
        case .paused:
            let path = NSBezierPath(roundedRect: NSRect(x: 1.0, y: 1.8, width: 16.0, height: 14.4), xRadius: 4, yRadius: 4)
            path.lineWidth = 1.4
            path.setLineDash([2, 2], count: 2, phase: 0)
            path.stroke()
        case .switching:
            let path = NSBezierPath()
            path.appendArc(
                withCenter: NSPoint(x: rect.midX, y: rect.midY),
                radius: 8,
                startAngle: 35,
                endAngle: 315,
                clockwise: false
            )
            path.lineCapStyle = .round
            path.lineWidth = 1.5
            path.stroke()
        case .failed:
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX, y: 1.4))
            path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 1.8))
            path.line(to: NSPoint(x: 2, y: rect.maxY - 1.8))
            path.close()
            path.lineWidth = 1.3
            path.stroke()
        }
    }

    private static func linkRect(for status: ProtectionStatus, size: NSSize) -> NSRect {
        switch status {
        case .protected, .onHotspot:
            NSRect(x: 3.0, y: 3.0, width: 12.0, height: 12.0)
        case .failed:
            NSRect(x: 4.6, y: 5.0, width: 8.8, height: 8.8)
        default:
            NSRect(x: 3.4, y: 3.2, width: 11.2, height: 11.2)
        }
    }

    private static func drawShieldOutline(in rect: NSRect) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.midX, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - 1.0, y: rect.minY + 5.0))
        path.line(to: NSPoint(x: rect.maxX - 1.6, y: rect.maxY - 2.4))
        path.line(to: NSPoint(x: rect.midX, y: rect.maxY - 0.8))
        path.line(to: NSPoint(x: rect.minX + 1.6, y: rect.maxY - 2.4))
        path.line(to: NSPoint(x: rect.minX + 1.0, y: rect.minY + 5.0))
        path.close()
        path.lineWidth = 1.85
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawSymbol(
        _ name: String,
        pointSize: CGFloat,
        weight: NSFont.Weight,
        in rect: NSRect
    ) {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)) else {
            return
        }

        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
