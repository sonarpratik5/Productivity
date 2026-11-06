import AppIntents
import Foundation
import SQLite3
import WidgetKit

struct CompleteGoalIntent: AppIntent {
    static var title: LocalizedStringResource = "Update Goal"
    static var description = IntentDescription("Marks or unmarks a FocusGrove goal for today.")

    @Parameter(title: "Goal ID")
    var goalID: String

    @Parameter(title: "Marker ID")
    var markerID: String

    @Parameter(title: "Done Today")
    var isDone: Bool

    init() {
        goalID = ""
        markerID = ""
        isDone = true
    }

    init(goalID: String, markerID: String, isDone: Bool) {
        self.goalID = goalID
        self.markerID = markerID
        self.isDone = isDone
    }

    func perform() async throws -> some IntentResult {
        let normalizedMarkerID = Self.normalizedMarkerID(markerID)
        guard !normalizedMarkerID.isEmpty else {
            return .result()
        }

        let didChange = WidgetCalendarBoardStore.setDoneToday(markerID: normalizedMarkerID, isDone: isDone)
        if didChange {
            updateSnapshot(markerID: normalizedMarkerID)
            postBoardChangedNotification()
        }

        WidgetCenter.shared.reloadTimelines(ofKind: ProductivityWidgetSnapshot.todayGoalsWidgetKind)
        return .result()
    }

    private func updateSnapshot(markerID: String) {
        guard var snapshot = ProductivityWidgetSnapshot.load() else { return }

        snapshot.updatedAt = Date()
        snapshot.goals = snapshot.goals.map { goal in
            guard goal.goalID?.uuidString == goalID || goal.markerID == markerID else {
                return goal
            }

            var updatedGoal = goal
            if updatedGoal.isDoneToday != isDone {
                updatedGoal.completedCount += isDone ? 1 : -1
            }
            updatedGoal.completedCount = min(max(0, updatedGoal.completedCount), updatedGoal.targetCount)
            updatedGoal.isDoneToday = isDone
            return updatedGoal
        }
        snapshot.save()
    }

    private func postBoardChangedNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(ProductivityWidgetSnapshot.boardChangedNotificationName as CFString),
            nil,
            nil,
            true
        )
    }

    fileprivate static func normalizedMarkerID(_ value: String) -> String {
        let legacyMap = [
            "★": "star",
            "⭐": "star",
            "◉": "workout",
            "🏃": "workout",
            "✦": "study",
            "📚": "study",
            "◌": "food",
            "🍽️": "food",
            "✓": "mindful",
            "🧘": "mindful"
        ]

        return legacyMap[value] ?? value
    }
}

private enum WidgetCalendarBoardStore {
    static func setDoneToday(markerID: String, isDone: Bool) -> Bool {
        guard let url = databaseURL,
              FileManager.default.fileExists(atPath: url.path) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &db,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else { return false }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 250)
        guard sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION", nil, nil, nil) == SQLITE_OK else {
            return false
        }

        let key = dayKey(for: Date())
        let didChange = setDoneToday(markerID: markerID, isDone: isDone, dayKey: key, database: db)
        guard didChange else {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            return false
        }

        return sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK
    }

    private static func setDoneToday(
        markerID: String,
        isDone: Bool,
        dayKey key: String,
        database db: OpaquePointer?
    ) -> Bool {
        var checkStmt: OpaquePointer?
        guard sqlite3_prepare_v2(db,
            "SELECT COUNT(*) FROM pins WHERE day_key = ? AND marker_id = ?",
            -1, &checkStmt, nil
        ) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(checkStmt) }

        sqlite3_bind_text(checkStmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(checkStmt, 2, markerID, -1, sqliteTransient)
        let alreadyDone = sqlite3_step(checkStmt) == SQLITE_ROW && sqlite3_column_int(checkStmt, 0) > 0

        guard alreadyDone != isDone else { return false }

        var mutStmt: OpaquePointer?
        let sql = isDone
            ? "INSERT OR IGNORE INTO pins (day_key, marker_id) VALUES (?, ?)"
            : "DELETE FROM pins WHERE day_key = ? AND marker_id = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &mutStmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(mutStmt) }

        sqlite3_bind_text(mutStmt, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(mutStmt, 2, markerID, -1, sqliteTransient)
        return sqlite3_step(mutStmt) == SQLITE_DONE && sqlite3_changes(db) > 0
    }

    private static var databaseURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: ProductivityWidgetSnapshot.appGroupIdentifier)?
            .appendingPathComponent("CalendarBoard", isDirectory: true)
            .appendingPathComponent("board.sqlite")
    }

    private static func dayKey(for date: Date) -> String {
        keyFormatter.string(from: Calendar.current.startOfDay(for: date))
    }

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
