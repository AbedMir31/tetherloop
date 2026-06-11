import AppKit
import SwiftUI
import TetherLoopCore

@MainActor
func render<V: View>(_ view: V, size: CGSize, to path: String) throws {
    let hostingView = NSHostingView(rootView: view)
    hostingView.frame = CGRect(origin: .zero, size: size)
    hostingView.layoutSubtreeIfNeeded()

    guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
        throw ScreenshotError.bitmapCreationFailed
    }
    hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw ScreenshotError.pngCreationFailed
    }

    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

enum ScreenshotError: Error {
    case bitmapCreationFailed
    case pngCreationFailed
}

@main
struct GenerateScreenshots {
    static func main() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let output = root.appendingPathComponent("assets/screenshots")
        let model = AppModel.preview()

        try await MainActor.run {
            try render(
                OnboardingView(model: model)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: CGSize(width: 1200, height: 820),
                to: output.appendingPathComponent("onboarding.png").path
            )
            try render(
                SettingsView(model: model)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: CGSize(width: 1100, height: 760),
                to: output.appendingPathComponent("settings.png").path
            )
            try render(
                TetherLoopMenu(model: model)
                    .padding(20)
                    .background(Color(nsColor: .windowBackgroundColor)),
                size: CGSize(width: 520, height: 520),
                to: output.appendingPathComponent("menu.png").path
            )
        }
    }
}
