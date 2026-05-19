import Foundation

/// Tracks usage statistics for the web dashboard.
class StatsTracker: ObservableObject {
    struct RequestRecord: Codable {
        let timestamp: Date
        let engine: String       // "local" | "cloud"
        let action: String
        let durationSeconds: Double
        let tokenCount: Int
    }

    @Published private(set) var records: [RequestRecord] = []
    @Published private(set) var sessionCount: Int = 0

    private let maxRecords = 500

    // MARK: - Record a completed request

    func record(engine: AIEngine, action: String, duration: Double, tokens: Int) {
        let rec = RequestRecord(
            timestamp: Date(),
            engine: engine == .cloud ? "cloud" : "local",
            action: action,
            durationSeconds: duration,
            tokenCount: tokens
        )
        records.append(rec)
        if records.count > maxRecords {
            records.removeFirst(records.count - maxRecords)
        }
        persistToDisk()
    }

    func incrementSessionCount() {
        sessionCount += 1
    }

    // MARK: - Aggregated stats (for dashboard JSON)

    var statsJSON: [String: Any] {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)
        let todayRecords = records.filter { $0.timestamp >= todayStart }
        let localCount = todayRecords.filter { $0.engine == "local" }.count
        let cloudCount = todayRecords.filter { $0.engine == "cloud" }.count
        let avgDuration = todayRecords.isEmpty ? 0.0
            : todayRecords.map(\.durationSeconds).reduce(0, +) / Double(todayRecords.count)
        let totalTokens = todayRecords.map(\.tokenCount).reduce(0, +)

        let recentActions = records.suffix(10).reversed().map { r -> [String: Any] in
            [
                "time": ISO8601DateFormatter().string(from: r.timestamp),
                "engine": r.engine,
                "action": r.action,
                "duration": String(format: "%.2f", r.durationSeconds),
                "tokens": r.tokenCount
            ]
        }

        return [
            "todayRequests": todayRecords.count,
            "localRequests": localCount,
            "cloudRequests": cloudCount,
            "avgDurationSec": String(format: "%.2f", avgDuration),
            "totalTokensToday": totalTokens,
            "sessionsCreated": sessionCount,
            "recentRequests": recentActions
        ]
    }

    // MARK: - Persistence

    private var statsFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first.map { $0.appendingPathComponent("MacSynergy/stats.json") }
    }

    private func persistToDisk() {
        guard let url = statsFileURL else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(records) {
            try? data.write(to: url)
        }
    }

    func loadFromDisk() {
        guard let url = statsFileURL,
              let data = try? Data(contentsOf: url),
              let loaded = try? JSONDecoder().decode([RequestRecord].self, from: data) else { return }
        records = loaded
    }
}
