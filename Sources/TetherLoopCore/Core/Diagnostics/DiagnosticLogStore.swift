import Foundation

public protocol DiagnosticLogStoring {
    func loadEvents() -> [DiagnosticEvent]
    func append(_ event: DiagnosticEvent)
}

public final class InMemoryDiagnosticLogStore: DiagnosticLogStoring {
    private var events: [DiagnosticEvent]
    private let limit: Int

    public init(events: [DiagnosticEvent] = [], limit: Int = 200) {
        self.events = events
        self.limit = limit
    }

    public func loadEvents() -> [DiagnosticEvent] {
        events
    }

    public func append(_ event: DiagnosticEvent) {
        events.append(event)
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
    }
}

public final class FileDiagnosticLogStore: DiagnosticLogStoring {
    private let fileURL: URL
    private let limit: Int

    public init(fileURL: URL? = nil, limit: Int = 500) {
        self.limit = limit
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appendingPathComponent("TetherLoop/diagnostics.json")
        }
    }

    public func loadEvents() -> [DiagnosticEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let events = try? JSONDecoder().decode([DiagnosticEvent].self, from: data) else {
            return []
        }
        return events
    }

    public func append(_ event: DiagnosticEvent) {
        var events = loadEvents()
        events.append(event)
        if events.count > limit {
            events.removeFirst(events.count - limit)
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Diagnostics must never crash the app.
        }
    }
}
