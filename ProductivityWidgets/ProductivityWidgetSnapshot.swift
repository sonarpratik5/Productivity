import Foundation

struct ProductivityWidgetSnapshot: Codable, Equatable {
    nonisolated static let appGroupIdentifier = "group.me.productivity"
    nonisolated static let storageKey = "productivity.widget.snapshot"
    nonisolated static let overviewWidgetKind = "me.Productivity.widgets.overview"
    nonisolated static let todayGoalsWidgetKind = "me.Productivity.widgets.todayGoals"
    nonisolated static let boardChangedNotificationName = "me.Productivity.widgets.boardChanged"

    var updatedAt: Date
    var productivityPercentage: Int
    var productiveMinutes: Int
    var trackedMinutes: Int
    var currentTrackingTitle: String
    var currentTrackingSubtitle: String
    var isTrackingEnabled: Bool
    var trackingStatusTitle: String
    var pomodoroPhaseTitle: String
    var pomodoroRemainingSeconds: TimeInterval
    var pomodoroTotalSeconds: TimeInterval
    var isPomodoroRunning: Bool
    var pomodoroUpdatedAt: Date
    var completedPomodorosToday: Int
    var goals: [ProductivityWidgetGoalSnapshot]

    static let empty = ProductivityWidgetSnapshot(
        updatedAt: Date(),
        productivityPercentage: 0,
        productiveMinutes: 0,
        trackedMinutes: 0,
        currentTrackingTitle: "Not tracking",
        currentTrackingSubtitle: "Open FocusGrove to start",
        isTrackingEnabled: false,
        trackingStatusTitle: "Off",
        pomodoroPhaseTitle: "Focus",
        pomodoroRemainingSeconds: 25 * 60,
        pomodoroTotalSeconds: 25 * 60,
        isPomodoroRunning: false,
        pomodoroUpdatedAt: Date(),
        completedPomodorosToday: 0,
        goals: []
    )

    static let placeholder = ProductivityWidgetSnapshot(
        updatedAt: Date(),
        productivityPercentage: 68,
        productiveMinutes: 145,
        trackedMinutes: 215,
        currentTrackingTitle: "Xcode",
        currentTrackingSubtitle: "Productive focus",
        isTrackingEnabled: true,
        trackingStatusTitle: "Tracking",
        pomodoroPhaseTitle: "Focus",
        pomodoroRemainingSeconds: 18 * 60,
        pomodoroTotalSeconds: 25 * 60,
        isPomodoroRunning: true,
        pomodoroUpdatedAt: Date(),
        completedPomodorosToday: 3,
        goals: [
            ProductivityWidgetGoalSnapshot(
                goalID: UUID(),
                markerID: "focus",
                name: "Deep Focus",
                symbol: "scope",
                completedCount: 4,
                targetCount: 5,
                periodTitle: "this week",
                isDoneToday: true
            ),
            ProductivityWidgetGoalSnapshot(
                goalID: UUID(),
                markerID: "workout",
                name: "Workout",
                symbol: "figure.run",
                completedCount: 2,
                targetCount: 3,
                periodTitle: "this week",
                isDoneToday: false
            ),
            ProductivityWidgetGoalSnapshot(
                goalID: UUID(),
                markerID: "writing",
                name: "Writing",
                symbol: "pencil.line",
                completedCount: 8,
                targetCount: 12,
                periodTitle: "this month",
                isDoneToday: true
            )
        ]
    )

    static var snapshotFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("widget_snapshot.json")
    }

    static func load() -> ProductivityWidgetSnapshot? {
        guard let url = snapshotFileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProductivityWidgetSnapshot.self, from: data)
    }

    @discardableResult
    func save() -> Bool {
        guard let url = Self.snapshotFileURL,
              let data = try? Self.encoder.encode(self) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()
}

struct ProductivityWidgetGoalSnapshot: Identifiable, Codable, Equatable {
    var id: String { goalID?.uuidString ?? name + periodTitle }

    var goalID: UUID?
    var markerID: String?
    var name: String
    var symbol: String
    var completedCount: Int
    var targetCount: Int
    var periodTitle: String
    var isDoneToday: Bool?

    init(
        goalID: UUID? = nil,
        markerID: String? = nil,
        name: String,
        symbol: String,
        completedCount: Int,
        targetCount: Int,
        periodTitle: String,
        isDoneToday: Bool? = nil
    ) {
        self.goalID = goalID
        self.markerID = markerID
        self.name = name
        self.symbol = symbol
        self.completedCount = completedCount
        self.targetCount = targetCount
        self.periodTitle = periodTitle
        self.isDoneToday = isDoneToday
    }

    var progress: Double {
        guard targetCount > 0 else { return 0 }
        return min(1, max(0, Double(completedCount) / Double(targetCount)))
    }

    var statusTitle: String {
        completedCount >= targetCount ? "Complete" : "\(max(0, targetCount - completedCount)) to go"
    }
}
