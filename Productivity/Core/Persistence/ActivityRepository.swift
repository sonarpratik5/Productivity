import Foundation
import SQLite3

protocol ActivityRepository: Sendable {
    func allSegments() async throws -> [ActivitySegment]
    func segments(for interval: DateInterval) async throws -> [ActivitySegment]
    func save(_ segments: [ActivitySegment]) async throws
    func deleteSegments(identifiedBy ids: Set<UUID>) async throws
    func deleteAllSegments() async throws
    func flush() async throws
}

protocol TimelineLabelRepository: Sendable {
    func allLabelSegments() async throws -> [TimelineLabelSegment]
    func labelSegments(for interval: DateInterval) async throws -> [TimelineLabelSegment]
    func replaceLabelSegments(_ segments: [TimelineLabelSegment], in interval: DateInterval) async throws
    func deleteAllLabelSegments() async throws
}

final actor InMemoryActivityRepository: ActivityRepository {
    private var segments: [ActivitySegment]

    init(segments: [ActivitySegment] = []) {
        self.segments = segments
    }

    func allSegments() async throws -> [ActivitySegment] {
        Self.sorted(segments)
    }

    func segments(for interval: DateInterval) async throws -> [ActivitySegment] {
        segments.filter { segment in
            guard let segmentInterval = segment.safeInterval else { return false }
            return SegmentOps.strictlyIntersects(interval, segmentInterval)
        }
    }

    func save(_ segments: [ActivitySegment]) async throws {
        var segmentsByID = Dictionary(uniqueKeysWithValues: self.segments.map { ($0.id, $0) })
        for segment in segments where segment.endDate > segment.startDate {
            if let existing = segmentsByID[segment.id] {
                segmentsByID[segment.id] = segment.endDate >= existing.endDate ? segment : existing
            } else {
                segmentsByID[segment.id] = segment
            }
        }
        self.segments = Self.sorted(Array(segmentsByID.values))
    }

    func deleteSegments(identifiedBy ids: Set<UUID>) async throws {
        segments.removeAll { ids.contains($0.id) }
    }

    func deleteAllSegments() async throws {
        segments.removeAll()
    }

    func flush() async throws {}

    nonisolated private static func sorted(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
    }
}

final actor InMemoryTimelineLabelRepository: TimelineLabelRepository {
    private var segments: [TimelineLabelSegment]

    init(segments: [TimelineLabelSegment] = []) {
        self.segments = segments
    }

    func allLabelSegments() async throws -> [TimelineLabelSegment] {
        Self.sorted(segments)
    }

    func labelSegments(for interval: DateInterval) async throws -> [TimelineLabelSegment] {
        Self.sorted(segments.filter { segment in
            guard segment.endDate > segment.startDate else { return false }
            return SegmentOps.strictlyIntersects(interval, DateInterval(start: segment.startDate, end: segment.endDate))
        })
    }

    func replaceLabelSegments(_ segments: [TimelineLabelSegment], in interval: DateInterval) async throws {
        let replacementSegments = TimelineLabelSegment.normalized(SegmentOps.clamped(segments, to: interval))
        let retainedSegments = self.segments.flatMap { SegmentOps.pieces(of: $0, outside: interval) }
        self.segments = Self.sorted(TimelineLabelSegment.normalized(retainedSegments + replacementSegments))
    }

    func deleteAllLabelSegments() async throws {
        segments.removeAll()
    }

    nonisolated private static func sorted(_ segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
    }
}

final class SQLiteBackedActivityRepository: ActivityRepository, @unchecked Sendable {
    fileprivate let ioQueue = DispatchQueue(
        label: "productivity.activity.sqlite",
        qos: .utility,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    private let databaseURL: URL
    private let legacyRootDirectory: URL?
    private let calendar: Calendar
    fileprivate var database: OpaquePointer?
    fileprivate var initializationError: Error?

    init(
        databaseURL: URL? = nil,
        legacyRootDirectory: URL? = nil,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        migratesLegacyStore: Bool = true
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(fileManager: fileManager)
        self.legacyRootDirectory = migratesLegacyStore
            ? (legacyRootDirectory ?? Self.defaultLegacyRootDirectory(fileManager: fileManager))
            : nil
        self.calendar = calendar
        try? fileManager.createDirectory(at: self.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        ioQueue.sync {
            do {
                try openDatabase()
                try migrateLegacyStoreIfNeeded(fileManager: fileManager)
            } catch {
                initializationError = error
                assertionFailure("Failed to initialize SQLite activity store: \(error)")
            }
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
        database = nil
    }

    func allSegments() async throws -> [ActivitySegment] {
        try await perform {
            try self.fetchSegments(sql: """
                SELECT id, app_name, bundle_identifier, title, user_description, start_date, end_date, category, label, productivity_score
                FROM activity_segments
                ORDER BY start_date, end_date
                """)
        }
    }

    func segments(for interval: DateInterval) async throws -> [ActivitySegment] {
        try await perform {
            try self.fetchSegments(
                sql: """
                    SELECT id, app_name, bundle_identifier, title, user_description, start_date, end_date, category, label, productivity_score
                    FROM activity_segments
                    WHERE start_date < ? AND end_date > ?
                    ORDER BY start_date, end_date
                    """,
                bind: { statement in
                    sqlite3_bind_double(statement, 1, interval.end.timeIntervalSinceReferenceDate)
                    sqlite3_bind_double(statement, 2, interval.start.timeIntervalSinceReferenceDate)
                }
            )
        }
    }

    func save(_ segments: [ActivitySegment]) async throws {
        try await perform {
            try self.saveLocked(segments)
        }
    }

    func deleteSegments(identifiedBy ids: Set<UUID>) async throws {
        try await perform {
            guard !ids.isEmpty else { return }
            try self.transaction {
                let statement = try self.prepare("DELETE FROM activity_segments WHERE id = ?")
                defer { sqlite3_finalize(statement) }
                for id in ids {
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                    sqlite3_bind_text(statement, 1, id.uuidString, -1, sqliteTransient)
                    try self.stepDone(statement)
                }
            }
        }
    }

    func deleteAllSegments() async throws {
        try await perform {
            try self.execute("DELETE FROM activity_segments")
        }
    }

    func flush() async throws {
        try await perform {
            try self.execute("PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    private func openDatabase() throws {
        guard database == nil else { return }
        if sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let openError = error()
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw openError
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=5000")
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS activity_segments (
                id TEXT PRIMARY KEY NOT NULL,
                app_name TEXT NOT NULL,
                bundle_identifier TEXT NOT NULL,
                title TEXT NOT NULL,
                user_description TEXT,
                start_date REAL NOT NULL,
                end_date REAL NOT NULL,
                category TEXT NOT NULL,
                label TEXT NOT NULL,
                productivity_score REAL NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_time_index ON activity_segments(start_date, end_date)")
        try execute("CREATE INDEX IF NOT EXISTS activity_segments_end_index ON activity_segments(end_date)")
    }

    private func saveLocked(_ segments: [ActivitySegment]) throws {
        let validSegments = segments.filter { $0.endDate > $0.startDate }
        guard !validSegments.isEmpty else { return }
        try transaction {
            try upsertSegments(validSegments)
        }
    }

    private func upsertSegments(_ validSegments: [ActivitySegment]) throws {
        let statement = try prepare("""
            INSERT INTO activity_segments (
                id, app_name, bundle_identifier, title, user_description, start_date, end_date, category, label, productivity_score
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                app_name = excluded.app_name,
                bundle_identifier = excluded.bundle_identifier,
                title = excluded.title,
                user_description = excluded.user_description,
                start_date = excluded.start_date,
                end_date = excluded.end_date,
                category = excluded.category,
                label = excluded.label,
                productivity_score = excluded.productivity_score
            WHERE excluded.end_date >= activity_segments.end_date
            """)
        defer { sqlite3_finalize(statement) }

        for segment in validSegments {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            bind(segment, to: statement)
            try stepDone(statement)
        }
    }

    private func migrateLegacyStoreIfNeeded(fileManager: FileManager) throws {
        guard metadataValue(for: "legacy_activity_segments_migrated") == nil else { return }
        guard let legacyRootDirectory, fileManager.fileExists(atPath: legacyRootDirectory.path) else {
            try setMetadataValue("1", for: "legacy_activity_segments_migrated")
            return
        }

        let segments = try Self.legacyActivitySegments(in: legacyRootDirectory, fileManager: fileManager)
        try transaction {
            let validSegments = segments.filter { $0.endDate > $0.startDate }
            if !validSegments.isEmpty {
                try upsertSegments(validSegments)
            }
            try setMetadataValue("1", for: "legacy_activity_segments_migrated")
        }
    }

    private func bind(_ segment: ActivitySegment, to statement: OpaquePointer?) {
        sqlite3_bind_text(statement, 1, segment.id.uuidString, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, segment.appName, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, segment.bundleIdentifier, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, segment.title, -1, sqliteTransient)
        if let userDescription = segment.userDescription {
            sqlite3_bind_text(statement, 5, userDescription, -1, sqliteTransient)
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_double(statement, 6, segment.startDate.timeIntervalSinceReferenceDate)
        sqlite3_bind_double(statement, 7, segment.endDate.timeIntervalSinceReferenceDate)
        sqlite3_bind_text(statement, 8, segment.category.rawValue, -1, sqliteTransient)
        sqlite3_bind_text(statement, 9, segment.label.id, -1, sqliteTransient)
        sqlite3_bind_double(statement, 10, segment.productivityScore)
    }

    private func fetchSegments(sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws -> [ActivitySegment] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement)

        var segments: [ActivitySegment] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let id = UUID(uuidString: Self.text(statement, 0)),
                  let category = ActivityCategory(rawValue: Self.text(statement, 7)) else {
                result = sqlite3_step(statement)
                continue
            }

            segments.append(ActivitySegment(
                id: id,
                appName: Self.text(statement, 1),
                bundleIdentifier: Self.text(statement, 2),
                title: Self.text(statement, 3),
                userDescription: Self.optionalText(statement, 4),
                startDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 5)),
                endDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 6)),
                category: category,
                label: ActivityLabel(id: Self.text(statement, 8)),
                productivityScore: sqlite3_column_double(statement, 9)
            ))
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw error()
        }
        return segments.filter { $0.endDate > $0.startDate }
    }

    private static func defaultDatabaseURL(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ActivityStore", isDirectory: false)
            .appendingPathExtension("sqlite")
    }

    private static func defaultLegacyRootDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ActivitySegments", isDirectory: true)
    }

    private static func legacyActivitySegments(in rootDirectory: URL, fileManager: FileManager) throws -> [ActivitySegment] {
        let decoder = PropertyListDecoder()
        var segmentsByID: [UUID: ActivitySegment] = [:]
        let urls = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in urls where url.pathExtension == "activitysegments" {
            guard let data = try? Data(contentsOf: url),
                  let segments = try? decoder.decode([ActivitySegment].self, from: data) else {
                continue
            }
            mergeLegacyActivitySegments(segments, into: &segmentsByID)
        }

        let journalURL = rootDirectory.appendingPathComponent("segments.wal", isDirectory: false)
        if let journalData = try? Data(contentsOf: journalURL) {
            mergeLegacyActivitySegments(fromJournalData: journalData, decoder: decoder, into: &segmentsByID)
        }

        return sorted(Array(segmentsByID.values))
    }

    private static func mergeLegacyActivitySegments(_ segments: [ActivitySegment], into segmentsByID: inout [UUID: ActivitySegment]) {
        for segment in segments where segment.endDate > segment.startDate {
            if let existing = segmentsByID[segment.id] {
                segmentsByID[segment.id] = segment.endDate >= existing.endDate ? segment : existing
            } else {
                segmentsByID[segment.id] = segment
            }
        }
    }

    private static func mergeLegacyActivitySegments(
        fromJournalData data: Data,
        decoder: PropertyListDecoder,
        into segmentsByID: inout [UUID: ActivitySegment]
    ) {
        var offset = 0
        let headerLength = MemoryLayout<UInt32>.size
        while offset + headerLength <= data.count {
            let lengthData = data[offset..<offset + headerLength]
            let payloadLength = Int(lengthData.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) })
            offset += headerLength
            guard payloadLength >= 0, offset + payloadLength <= data.count else { break }
            let payload = data[offset..<offset + payloadLength]
            offset += payloadLength
            guard let segments = try? decoder.decode([ActivitySegment].self, from: Data(payload)) else { continue }
            mergeLegacyActivitySegments(segments, into: &segmentsByID)
        }
    }

    private static func sorted(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.sorted {
            if $0.startDate == $1.startDate { return $0.endDate < $1.endDate }
            return $0.startDate < $1.startDate
        }
    }
}

final class SQLiteBackedTimelineLabelRepository: TimelineLabelRepository, @unchecked Sendable {
    fileprivate let ioQueue = DispatchQueue(
        label: "productivity.timelabels.sqlite",
        qos: .utility,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    private let databaseURL: URL
    private let legacyRootDirectory: URL?
    private let calendar: Calendar
    fileprivate var database: OpaquePointer?
    fileprivate var initializationError: Error?

    init(
        databaseURL: URL? = nil,
        legacyRootDirectory: URL? = nil,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        migratesLegacyStore: Bool = true
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(fileManager: fileManager)
        self.legacyRootDirectory = migratesLegacyStore
            ? (legacyRootDirectory ?? Self.defaultLegacyRootDirectory(fileManager: fileManager))
            : nil
        self.calendar = calendar
        try? fileManager.createDirectory(at: self.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        ioQueue.sync {
            do {
                try openDatabase()
                try migrateLegacyStoreIfNeeded(fileManager: fileManager)
            } catch {
                initializationError = error
                assertionFailure("Failed to initialize SQLite timeline label store: \(error)")
            }
        }
    }

    deinit {
        if let database {
            sqlite3_close(database)
        }
        database = nil
    }

    func allLabelSegments() async throws -> [TimelineLabelSegment] {
        try await perform {
            try TimelineLabelSegment.normalized(self.fetchLabels(sql: """
                SELECT id, label, start_date, end_date
                FROM timeline_label_segments
                ORDER BY start_date, end_date
                """))
        }
    }

    func labelSegments(for interval: DateInterval) async throws -> [TimelineLabelSegment] {
        try await perform {
            try TimelineLabelSegment.normalized(self.fetchLabels(
                sql: """
                    SELECT id, label, start_date, end_date
                    FROM timeline_label_segments
                    WHERE start_date < ? AND end_date > ?
                    ORDER BY start_date, end_date
                    """,
                bind: { statement in
                    sqlite3_bind_double(statement, 1, interval.end.timeIntervalSinceReferenceDate)
                    sqlite3_bind_double(statement, 2, interval.start.timeIntervalSinceReferenceDate)
                }
            ))
        }
    }

    func replaceLabelSegments(_ segments: [TimelineLabelSegment], in interval: DateInterval) async throws {
        try await perform {
            let replacementSegments = TimelineLabelSegment.normalized(SegmentOps.clamped(segments, to: interval))
            let overlappingSegments = try self.fetchLabels(
                sql: """
                    SELECT id, label, start_date, end_date
                    FROM timeline_label_segments
                    WHERE start_date < ? AND end_date > ?
                    ORDER BY start_date, end_date
                    """,
                bind: { statement in
                    sqlite3_bind_double(statement, 1, interval.end.timeIntervalSinceReferenceDate)
                    sqlite3_bind_double(statement, 2, interval.start.timeIntervalSinceReferenceDate)
                }
            )
            let retainedSegments = overlappingSegments.flatMap { SegmentOps.pieces(of: $0, outside: interval) }
            let updatedSegments = TimelineLabelSegment.normalized(retainedSegments + replacementSegments)

            try self.transaction {
                let deleteStatement = try self.prepare("DELETE FROM timeline_label_segments WHERE start_date < ? AND end_date > ?")
                defer { sqlite3_finalize(deleteStatement) }
                sqlite3_bind_double(deleteStatement, 1, interval.end.timeIntervalSinceReferenceDate)
                sqlite3_bind_double(deleteStatement, 2, interval.start.timeIntervalSinceReferenceDate)
                try self.stepDone(deleteStatement)

                try self.insertLabels(updatedSegments)
            }
        }
    }

    func deleteAllLabelSegments() async throws {
        try await perform {
            try self.execute("DELETE FROM timeline_label_segments")
        }
    }

    private func openDatabase() throws {
        guard database == nil else { return }
        if sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let openError = error()
            if let database {
                sqlite3_close(database)
            }
            database = nil
            throw openError
        }
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA foreign_keys=ON")
        try execute("PRAGMA busy_timeout=5000")
        try execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)
        try execute("""
            CREATE TABLE IF NOT EXISTS timeline_label_segments (
                id TEXT PRIMARY KEY NOT NULL,
                label TEXT NOT NULL,
                start_date REAL NOT NULL,
                end_date REAL NOT NULL
            )
            """)
        try execute("CREATE INDEX IF NOT EXISTS timeline_label_segments_time_index ON timeline_label_segments(start_date, end_date)")
        try execute("CREATE INDEX IF NOT EXISTS timeline_label_segments_end_index ON timeline_label_segments(end_date)")
    }

    private func insertLabels(_ labels: [TimelineLabelSegment]) throws {
        guard !labels.isEmpty else { return }
        let labelsToInsert = try labelsWithDatabaseUniqueIDs(labels)
        let statement = try prepare("""
            INSERT OR REPLACE INTO timeline_label_segments (id, label, start_date, end_date)
            VALUES (?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }

        for label in labelsToInsert where label.endDate > label.startDate {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            sqlite3_bind_text(statement, 1, label.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(statement, 2, label.label.id, -1, sqliteTransient)
            sqlite3_bind_double(statement, 3, label.startDate.timeIntervalSinceReferenceDate)
            sqlite3_bind_double(statement, 4, label.endDate.timeIntervalSinceReferenceDate)
            try stepDone(statement)
        }
    }

    private func labelsWithDatabaseUniqueIDs(_ labels: [TimelineLabelSegment]) throws -> [TimelineLabelSegment] {
        var usedIDs = Set<UUID>()
        let storedLabelsByID = try existingStoredLabelsByID(for: Set(labels.map(\.id)))
        return labels.map { label in
            guard label.endDate > label.startDate else { return label }
            var resolvedLabel = label
            while hasIDConflict(for: resolvedLabel, usedIDs: usedIDs, storedLabelsByID: storedLabelsByID) {
                resolvedLabel = TimelineLabelSegment(
                    id: UUID(),
                    label: resolvedLabel.label,
                    startDate: resolvedLabel.startDate,
                    endDate: resolvedLabel.endDate
                )
            }
            usedIDs.insert(resolvedLabel.id)
            return resolvedLabel
        }
    }

    private func hasIDConflict(
        for label: TimelineLabelSegment,
        usedIDs: Set<UUID>,
        storedLabelsByID: [UUID: StoredLabelSignature]
    ) -> Bool {
        if usedIDs.contains(label.id) {
            return true
        }

        guard let storedLabel = storedLabelsByID[label.id] else {
            return false
        }

        return storedLabel.labelID != label.label.id
            || storedLabel.startDate != label.startDate
            || storedLabel.endDate != label.endDate
    }

    private func existingStoredLabelsByID(for ids: Set<UUID>) throws -> [UUID: StoredLabelSignature] {
        guard !ids.isEmpty else { return [:] }

        var storedLabelsByID: [UUID: StoredLabelSignature] = [:]
        let idValues = Array(ids)
        for chunkStart in stride(from: 0, to: idValues.count, by: 500) {
            let chunk = Array(idValues[chunkStart..<min(chunkStart + 500, idValues.count)])
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let statement = try prepare("""
                SELECT id, label, start_date, end_date
                FROM timeline_label_segments
                WHERE id IN (\(placeholders))
                """)
            defer { sqlite3_finalize(statement) }

            for (index, id) in chunk.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), id.uuidString, -1, sqliteTransient)
            }

            var result = sqlite3_step(statement)
            while result == SQLITE_ROW {
                if let id = UUID(uuidString: Self.text(statement, 0)) {
                    storedLabelsByID[id] = StoredLabelSignature(
                        labelID: Self.text(statement, 1),
                        startDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                        endDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
                    )
                }
                result = sqlite3_step(statement)
            }

            guard result == SQLITE_DONE else {
                throw error()
            }
        }

        return storedLabelsByID
    }

    private struct StoredLabelSignature {
        let labelID: String
        let startDate: Date
        let endDate: Date
    }

    private func migrateLegacyStoreIfNeeded(fileManager: FileManager) throws {
        guard metadataValue(for: "legacy_timeline_labels_migrated") == nil else { return }
        guard let legacyRootDirectory, fileManager.fileExists(atPath: legacyRootDirectory.path) else {
            try setMetadataValue("1", for: "legacy_timeline_labels_migrated")
            return
        }

        try transaction {
            try insertLabels(Self.legacyLabelSegments(in: legacyRootDirectory, fileManager: fileManager))
            try setMetadataValue("1", for: "legacy_timeline_labels_migrated")
        }
    }

    private func fetchLabels(sql: String, bind: (OpaquePointer?) -> Void = { _ in }) throws -> [TimelineLabelSegment] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement)

        var labels: [TimelineLabelSegment] = []
        var result = sqlite3_step(statement)
        while result == SQLITE_ROW {
            guard let id = UUID(uuidString: Self.text(statement, 0)) else {
                result = sqlite3_step(statement)
                continue
            }
            labels.append(TimelineLabelSegment(
                id: id,
                label: ActivityLabel(id: Self.text(statement, 1)),
                startDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 2)),
                endDate: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3))
            ))
            result = sqlite3_step(statement)
        }

        guard result == SQLITE_DONE else {
            throw error()
        }
        return labels.filter { $0.endDate > $0.startDate }
    }

    private static func defaultDatabaseURL(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ActivityStore", isDirectory: false)
            .appendingPathExtension("sqlite")
    }

    private static func defaultLegacyRootDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("TimelineLabels", isDirectory: true)
    }

    private static func legacyLabelSegments(in rootDirectory: URL, fileManager: FileManager) throws -> [TimelineLabelSegment] {
        let decoder = PropertyListDecoder()
        let urls = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let segments = urls
            .filter { $0.pathExtension == "timelinelabels" }
            .flatMap { url -> [TimelineLabelSegment] in
                guard let data = try? Data(contentsOf: url),
                      let labels = try? decoder.decode([TimelineLabelSegment].self, from: data) else {
                    return []
                }
                return labels
            }

        return TimelineLabelSegment.normalized(segments)
    }

}

private enum SegmentOps {
    nonisolated static func strictlyIntersects(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }

    nonisolated static func clamped(_ segments: [TimelineLabelSegment], to interval: DateInterval) -> [TimelineLabelSegment] {
        segments.compactMap { segment in
            guard segment.endDate > segment.startDate else { return nil }
            let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
            guard strictlyIntersects(interval, segmentInterval) else { return nil }
            let startDate = max(segment.startDate, interval.start)
            let endDate = min(segment.endDate, interval.end)
            guard endDate > startDate else { return nil }
            return TimelineLabelSegment(id: segment.id, label: segment.label, startDate: startDate, endDate: endDate)
        }
    }

    nonisolated static func pieces(of segment: TimelineLabelSegment, outside interval: DateInterval) -> [TimelineLabelSegment] {
        guard segment.endDate > segment.startDate else { return [] }
        let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
        guard strictlyIntersects(interval, segmentInterval) else { return [segment] }
        var result: [TimelineLabelSegment] = []
        if interval.start > segment.startDate {
            result.append(TimelineLabelSegment(
                id: segment.id,
                label: segment.label,
                startDate: segment.startDate,
                endDate: min(interval.start, segment.endDate)
            ))
        }
        if interval.end < segment.endDate {
            // New UUID for trailing piece when both pieces are produced — prevents two
            // TimelineLabelSegments with the same UUID violating Identifiable uniqueness.
            result.append(TimelineLabelSegment(
                id: result.isEmpty ? segment.id : UUID(),
                label: segment.label,
                startDate: max(interval.end, segment.startDate),
                endDate: segment.endDate
            ))
        }
        return result.filter { $0.endDate > $0.startDate }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private protocol SQLiteRepositoryStorage: AnyObject {
    var database: OpaquePointer? { get set }
    var initializationError: Error? { get set }
    var ioQueue: DispatchQueue { get }
}

extension SQLiteBackedActivityRepository: SQLiteRepositoryStorage {}
extension SQLiteBackedTimelineLabelRepository: SQLiteRepositoryStorage {}

private extension SQLiteRepositoryStorage {
    func perform<T>(_ body: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async {
                do {
                    if let initializationError = self.initializationError {
                        throw initializationError
                    }
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func execute(_ sql: String) throws {
        if sqlite3_exec(database, sql, nil, nil, nil) != SQLITE_OK {
            throw error()
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK {
            throw error()
        }
        return statement
    }

    func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw error()
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func metadataValue(for key: String) -> String? {
        guard let statement = try? prepare("SELECT value FROM metadata WHERE key = ?") else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return Self.optionalText(statement, 0)
    }

    func setMetadataValue(_ value: String, for key: String) throws {
        let statement = try prepare("INSERT OR REPLACE INTO metadata (key, value) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, value, -1, sqliteTransient)
        try stepDone(statement)
    }

    func error() -> Error {
        let code = sqlite3_errcode(database)
        let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unknown SQLite error"
        return NSError(
            domain: "Productivity.SQLite",
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }

    static func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        optionalText(statement, index) ?? ""
    }

    static func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: cString)
    }
}

final class FileBackedActivityRepository: ActivityRepository, @unchecked Sendable {
    private struct DayBucket {
        var segmentsByID: [UUID: ActivitySegment]
    }

    // All file I/O runs on this serial queue so callers (including the main actor) never block.
    private let ioQueue = DispatchQueue(
        label: "productivity.activity.io",
        qos: .utility,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let journalURL: URL
    private let segmentIndexURL: URL
    private let calendar: Calendar
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder
    private var buckets: [String: DayBucket] = [:]
    private var dirtyDayKeys = Set<String>()
    private var flushWorkItem: DispatchWorkItem?
    private var journalRecordCount = 0
    private var dayKeysBySegmentID: [UUID: Set<String>] = [:]
    private var hasCompleteSegmentIndex = false

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.calendar = calendar
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.journalURL = self.rootDirectory.appendingPathComponent("segments.wal", isDirectory: false)
        self.segmentIndexURL = self.rootDirectory.appendingPathComponent("segment-index", isDirectory: false)
            .appendingPathExtension("plist")
        self.encoder = PropertyListEncoder()
        self.decoder = PropertyListDecoder()
        self.encoder.outputFormat = .binary

        try? fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
        loadSegmentIndex()
        replayJournal()
    }

    func segments(for interval: DateInterval) async throws -> [ActivitySegment] {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    continuation.resume(returning: try segmentsLocked(for: interval))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func allSegments() async throws -> [ActivitySegment] {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    try flushLocked()
                    let segs = try persistedDayKeys().flatMap { dayKey in
                        try loadBucket(for: dayKey).segmentsByID.values
                    }
                    hasCompleteSegmentIndex = true
                    try writeSegmentIndex()
                    continuation.resume(returning: Self.sorted(Self.deduplicated(segs)))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func save(_ segments: [ActivitySegment]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    try saveLocked(segments)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteSegments(identifiedBy ids: Set<UUID>) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    try deleteSegmentsLocked(identifiedBy: ids)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteAllSegments() async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    try deleteAllSegmentsLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func flush() async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    try flushLocked()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func segmentsLocked(for interval: DateInterval) throws -> [ActivitySegment] {
        var segments: [ActivitySegment] = []
        for dayKey in dayKeys(overlapping: interval) {
            let bucket = try loadBucket(for: dayKey)
            segments.append(contentsOf: bucket.segmentsByID.values)
        }

        return Self.sorted(
            Self.deduplicated(segments)
                .filter { segment in
                    guard let segmentInterval = segment.safeInterval else { return false }
                    return SegmentOps.strictlyIntersects(interval, segmentInterval)
                }
        )
    }

    private func saveLocked(_ segments: [ActivitySegment]) throws {
        let validSegments = segments.filter { $0.endDate > $0.startDate }
        guard !validSegments.isEmpty else { return }

        var changedSegments: [ActivitySegment] = []
        for segment in validSegments {
            if dayKeysBySegmentID[segment.id] == nil {
                try completeSegmentIndexIfNeeded()
            }
            let oldDayKeys = dayKeysBySegmentID[segment.id] ?? []
            let existingSegment = try oldDayKeys
                .compactMap { try loadBucket(for: $0).segmentsByID[segment.id] }
                .max { $0.endDate < $1.endDate }
            let segmentToStore = existingSegment.map { existing in
                existing.endDate > segment.endDate ? existing : segment
            } ?? segment
            let segmentInterval = DateInterval(start: segmentToStore.startDate, end: segmentToStore.endDate)
            let targetDayKeys = Set(dayKeys(spannedBy: segmentInterval))
            let impactedDayKeys = oldDayKeys.union(targetDayKeys)
            var changedDayKeys = Set<String>()

            for dayKey in impactedDayKeys {
                var bucket = try loadBucket(for: dayKey)
                if targetDayKeys.contains(dayKey) {
                    if bucket.segmentsByID[segment.id] != segmentToStore {
                        bucket.segmentsByID[segment.id] = segmentToStore
                        changedDayKeys.insert(dayKey)
                    }
                } else if bucket.segmentsByID.removeValue(forKey: segment.id) != nil {
                    changedDayKeys.insert(dayKey)
                }

                guard changedDayKeys.contains(dayKey) else { continue }
                buckets[dayKey] = bucket
                dirtyDayKeys.insert(dayKey)
            }

            if !changedDayKeys.isEmpty {
                dayKeysBySegmentID[segment.id] = targetDayKeys
                changedSegments.append(segmentToStore)
            }
        }

        guard !changedSegments.isEmpty else { return }
        try appendJournalRecord(changedSegments)
        scheduleFlush()
    }

    private func deleteSegmentsLocked(identifiedBy ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }

        // Use the ID→dayKey index to avoid loading every persisted day file.
        // Any ID not yet indexed (not yet loaded into memory) falls back to a full scan.
        var knownDayKeys = Set<String>()
        var unindexedIDs = Set<UUID>()
        for id in ids {
            if let keys = dayKeysBySegmentID[id] {
                knownDayKeys.formUnion(keys)
            } else {
                unindexedIDs.insert(id)
            }
        }
        let dayKeysToScan = unindexedIDs.isEmpty
            ? knownDayKeys
            : knownDayKeys.union(try persistedDayKeys())

        for dayKey in dayKeysToScan {
            var bucket = try loadBucket(for: dayKey)
            let originalCount = bucket.segmentsByID.count
            bucket.segmentsByID = bucket.segmentsByID.filter { !ids.contains($0.key) }
            guard bucket.segmentsByID.count != originalCount else { continue }
            buckets[dayKey] = bucket
            dirtyDayKeys.insert(dayKey)
        }

        for id in ids {
            dayKeysBySegmentID.removeValue(forKey: id)
        }

        try flushLocked()
    }

    private func deleteAllSegmentsLocked() throws {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        buckets.removeAll()
        dirtyDayKeys.removeAll()
        journalRecordCount = 0
        dayKeysBySegmentID.removeAll()
        hasCompleteSegmentIndex = false

        if fileManager.fileExists(atPath: rootDirectory.path) {
            try fileManager.removeItem(at: rootDirectory)
        }
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func flushLocked() throws {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        guard !dirtyDayKeys.isEmpty else {
            try removeJournalIfNeeded()
            try writeSegmentIndex()
            return
        }

        let dayKeys = dirtyDayKeys
        for dayKey in dayKeys {
            guard let bucket = buckets[dayKey] else { continue }
            try writeBucket(bucket, for: dayKey)
        }

        dirtyDayKeys.subtract(dayKeys)
        if dirtyDayKeys.isEmpty {
            try removeJournalIfNeeded()
            journalRecordCount = 0
        }
        try writeSegmentIndex()
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ActivitySegments", isDirectory: true)
    }

    private func loadBucket(for dayKey: String) throws -> DayBucket {
        if let bucket = buckets[dayKey] {
            return bucket
        }

        let url = fileURL(for: dayKey)
        guard fileManager.fileExists(atPath: url.path) else {
            return DayBucket(segmentsByID: [:])
        }

        let data = try Data(contentsOf: url)
        let segments: [ActivitySegment]
        do {
            segments = try decoder.decode([ActivitySegment].self, from: data)
        } catch {
            try quarantineCorruptFile(at: url)
            let emptyBucket = DayBucket(segmentsByID: [:])
            buckets[dayKey] = emptyBucket
            return emptyBucket
        }
        let bucket = DayBucket(segmentsByID: segmentsByID(from: segments))
        buckets[dayKey] = bucket
        indexSegments(bucket.segmentsByID.values, in: dayKey)
        return bucket
    }

    private func writeBucket(_ bucket: DayBucket, for dayKey: String) throws {
        let url = fileURL(for: dayKey)
        let segments = Self.sorted(Array(bucket.segmentsByID.values))
        if segments.isEmpty {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        let data = try encoder.encode(segments)
        try data.write(to: url, options: [.atomic])
    }

    private func appendJournalRecord(_ segments: [ActivitySegment]) throws {
        let payload = try encoder.encode(segments)
        var length = UInt32(payload.count).bigEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)

        if !fileManager.fileExists(atPath: journalURL.path) {
            fileManager.createFile(atPath: journalURL.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: journalURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: payload)
        try handle.synchronize()
        journalRecordCount += 1
    }

    private func replayJournal() {
        guard let data = try? Data(contentsOf: journalURL), !data.isEmpty else { return }

        var offset = 0
        let headerLength = MemoryLayout<UInt32>.size
        while offset + headerLength <= data.count {
            let lengthData = data[offset..<offset + headerLength]
            let length = lengthData.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
            offset += headerLength

            let payloadLength = Int(length)
            guard payloadLength >= 0, offset + payloadLength <= data.count else { break }
            let payload = data[offset..<offset + payloadLength]
            offset += payloadLength

            guard let segments = try? decoder.decode([ActivitySegment].self, from: Data(payload)) else {
                continue
            }

            for segment in segments where segment.endDate > segment.startDate {
                let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
                for dayKey in dayKeys(spannedBy: segmentInterval) {
                    var bucket = buckets[dayKey] ?? DayBucket(segmentsByID: [:])
                    bucket.segmentsByID[segment.id] = segment
                    buckets[dayKey] = bucket
                    dirtyDayKeys.insert(dayKey)
                    dayKeysBySegmentID[segment.id, default: []].insert(dayKey)
                }
            }
            journalRecordCount += 1
        }
    }

    private func indexSegments(_ segments: some Collection<ActivitySegment>, in dayKey: String) {
        for segment in segments {
            dayKeysBySegmentID[segment.id, default: []].insert(dayKey)
        }
    }

    private func completeSegmentIndexIfNeeded() throws {
        guard !hasCompleteSegmentIndex else { return }
        for dayKey in try persistedDayKeys() {
            _ = try loadBucket(for: dayKey)
        }
        hasCompleteSegmentIndex = true
    }

    private func segmentsByID(from segments: [ActivitySegment]) -> [UUID: ActivitySegment] {
        var segmentsByID: [UUID: ActivitySegment] = [:]
        for segment in segments where segment.endDate > segment.startDate {
            if let existing = segmentsByID[segment.id] {
                segmentsByID[segment.id] = segment.endDate >= existing.endDate ? segment : existing
            } else {
                segmentsByID[segment.id] = segment
            }
        }
        return segmentsByID
    }

    private func scheduleFlush() {
        guard flushWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            // Already executing on ioQueue — call the internal locked helper directly.
            try? self?.flushLocked()
        }
        flushWorkItem = item
        ioQueue.asyncAfter(deadline: .now() + 30, execute: item)
    }

    private func removeJournalIfNeeded() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else { return }
        try fileManager.removeItem(at: journalURL)
    }

    private func loadSegmentIndex() {
        guard let data = try? Data(contentsOf: segmentIndexURL),
              let storedIndex = try? decoder.decode([UUID: Set<String>].self, from: data) else {
            return
        }

        dayKeysBySegmentID = storedIndex
        hasCompleteSegmentIndex = true
    }

    private func writeSegmentIndex() throws {
        guard hasCompleteSegmentIndex else { return }
        let data = try encoder.encode(dayKeysBySegmentID)
        try data.write(to: segmentIndexURL, options: [.atomic])
    }

    private func quarantineCorruptFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let quarantineURL = uniqueQuarantineURL(for: url)
        try fileManager.moveItem(at: url, to: quarantineURL)
    }

    private func uniqueQuarantineURL(for url: URL) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        var candidate = url.appendingPathExtension("corrupt-\(timestamp)")
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathExtension("corrupt-\(timestamp)-\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func dayKeys(overlapping interval: DateInterval) -> [String] {
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.start)) ?? interval.start
        let end = storageEndDayStart(for: interval)
        var date = start
        var keys: [String] = []

        while date <= end {
            keys.append(dayKey(for: date))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return keys
    }

    private func dayKeys(spannedBy interval: DateInterval) -> [String] {
        let start = calendar.startOfDay(for: interval.start)
        let end = storageEndDayStart(for: interval)
        var date = start
        var keys: [String] = []

        while date <= end {
            keys.append(dayKey(for: date))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return keys
    }

    private func storageEndDayStart(for interval: DateInterval) -> Date {
        let endDay = calendar.startOfDay(for: interval.end)
        if endDay == interval.end,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: endDay) {
            return max(previousDay, calendar.startOfDay(for: interval.start))
        }

        return endDay
    }

    private func persistedDayKeys() throws -> Set<String> {
        var keys = Set(buckets.keys)
        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension == "activitysegments" {
            keys.insert(url.deletingPathExtension().lastPathComponent)
        }

        return keys
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func fileURL(for dayKey: String) -> URL {
        rootDirectory.appendingPathComponent(dayKey, isDirectory: false)
            .appendingPathExtension("activitysegments")
    }

    nonisolated private static func deduplicated(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        var segmentsByID: [UUID: ActivitySegment] = [:]
        for segment in segments {
            if let existing = segmentsByID[segment.id] {
                segmentsByID[segment.id] = segment.endDate >= existing.endDate ? segment : existing
            } else {
                segmentsByID[segment.id] = segment
            }
        }
        return Array(segmentsByID.values)
    }

    nonisolated private static func sorted(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
    }
}

final class FileBackedTimelineLabelRepository: TimelineLabelRepository, @unchecked Sendable {
    private let ioQueue = DispatchQueue(
        label: "productivity.timelabels.io",
        qos: .utility,
        attributes: [],
        autoreleaseFrequency: .workItem
    )
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let calendar: Calendar
    private let encoder: PropertyListEncoder
    private let decoder: PropertyListDecoder
    private var buckets: [String: [TimelineLabelSegment]] = [:]

    init(
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil,
        calendar: Calendar = .current
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.calendar = calendar
        self.encoder = PropertyListEncoder()
        self.decoder = PropertyListDecoder()
        self.encoder.outputFormat = .binary

        try? fileManager.createDirectory(at: self.rootDirectory, withIntermediateDirectories: true)
    }

    func labelSegments(for interval: DateInterval) async throws -> [TimelineLabelSegment] {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    // Include the day before interval.start so label segments that started
                    // before midnight but extend into the interval are not silently dropped.
                    let segs = try readDayKeys(overlapping: interval).flatMap { dayKey in
                        try loadBucket(for: dayKey)
                    }
                    let result = TimelineLabelSegment.normalized(segs.filter { segment in
                        guard segment.endDate > segment.startDate else { return false }
                        return SegmentOps.strictlyIntersects(interval, DateInterval(start: segment.startDate, end: segment.endDate))
                    })
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func allLabelSegments() async throws -> [TimelineLabelSegment] {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    let segs = try persistedDayKeys().flatMap { dayKey in
                        try loadBucket(for: dayKey)
                    }
                    continuation.resume(returning: TimelineLabelSegment.normalized(segs))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func replaceLabelSegments(_ segments: [TimelineLabelSegment], in interval: DateInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    let normalizedSegments = TimelineLabelSegment.normalized(SegmentOps.clamped(segments, to: interval))
                    for dayKey in try writeDayKeys(replacing: interval, replacementSegments: normalizedSegments) {
                        let dayInterval = try intervalForDayKey(dayKey)
                        let retainedSegments = try loadBucket(for: dayKey).flatMap { SegmentOps.pieces(of: $0, outside: interval) }
                        let replacementSegments = normalizedSegments.compactMap { segment -> TimelineLabelSegment? in
                            guard segment.endDate > segment.startDate else { return nil }
                            let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
                            guard SegmentOps.strictlyIntersects(dayInterval, segmentInterval) else { return nil }

                            let startDate = max(segment.startDate, dayInterval.start)
                            let endDate = min(segment.endDate, dayInterval.end)
                            guard endDate > startDate else { return nil }
                            return TimelineLabelSegment(
                                id: segment.id,
                                label: segment.label,
                                startDate: startDate,
                                endDate: endDate
                            )
                        }

                        let updatedSegments = TimelineLabelSegment.normalized(retainedSegments + replacementSegments)
                        buckets[dayKey] = updatedSegments
                        try writeBucket(updatedSegments, for: dayKey)
                    }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deleteAllLabelSegments() async throws {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { [self] in
                do {
                    buckets.removeAll()
                    if fileManager.fileExists(atPath: rootDirectory.path) {
                        try fileManager.removeItem(at: rootDirectory)
                    }
                    try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let baseDirectory = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? fileManager.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("TimelineLabels", isDirectory: true)
    }

    private func loadBucket(for dayKey: String) throws -> [TimelineLabelSegment] {
        if let bucket = buckets[dayKey] {
            return bucket
        }

        let url = fileURL(for: dayKey)
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }

        let data = try Data(contentsOf: url)
        let segments: [TimelineLabelSegment]
        do {
            segments = try decoder.decode([TimelineLabelSegment].self, from: data)
        } catch {
            try quarantineCorruptFile(at: url)
            buckets[dayKey] = []
            return []
        }
        buckets[dayKey] = TimelineLabelSegment.normalized(segments.filter { $0.endDate > $0.startDate })
        return buckets[dayKey] ?? []
    }

    private func writeBucket(_ segments: [TimelineLabelSegment], for dayKey: String) throws {
        let url = fileURL(for: dayKey)
        if segments.isEmpty {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return
        }

        let data = try encoder.encode(Self.sorted(segments))
        try data.write(to: url, options: [.atomic])
    }

    // Extends one day before interval.start to catch midnight-spanning label segments
    // stored in the previous day's bucket. Used only for reads.
    private func readDayKeys(overlapping interval: DateInterval) -> [String] {
        let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.start))
            ?? calendar.startOfDay(for: interval.start)
        let end = storageEndDayStart(for: interval)
        var date = start
        var keys: [String] = []

        while date <= end {
            keys.append(dayKey(for: date))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return keys
    }

    private func storageEndDayStart(for interval: DateInterval) -> Date {
        let start = calendar.startOfDay(for: interval.start)
        let endDay = calendar.startOfDay(for: interval.end)
        if endDay == interval.end,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: endDay) {
            return max(previousDay, start)
        }

        return endDay
    }

    private func dayKeys(overlapping interval: DateInterval) -> [String] {
        let start = calendar.startOfDay(for: interval.start)
        // When the interval ends exactly at midnight, exclude that boundary day from write
        // operations — no replacement segment can strictly intersect it, and including it
        // causes a redundant read + write of the next day's bucket on every label edit.
        let end = storageEndDayStart(for: interval)
        var date = start
        var keys: [String] = []

        while date <= end {
            keys.append(dayKey(for: date))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return keys
    }

    private func writeDayKeys(replacing interval: DateInterval, replacementSegments: [TimelineLabelSegment]) throws -> [String] {
        var dayKeys = Set(dayKeys(overlapping: interval))
        let precedingDayStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: interval.start))
            ?? calendar.startOfDay(for: interval.start)
        let precedingDayKey = dayKey(for: precedingDayStart)
        let precedingDaySegments = try loadBucket(for: precedingDayKey)
        let replacementIDs = Set(replacementSegments.map(\.id))

        if precedingDaySegments.contains(where: { segment in
            guard segment.endDate > segment.startDate else { return false }
            guard !replacementIDs.contains(segment.id) else { return true }
            return SegmentOps.strictlyIntersects(interval, DateInterval(start: segment.startDate, end: segment.endDate))
        }) {
            dayKeys.insert(precedingDayKey)
        }

        return dayKeys.sorted()
    }

    private func intervalForDayKey(_ dayKey: String) throws -> DateInterval {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let interval = calendar.dateInterval(of: .day, for: date) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return interval
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func fileURL(for dayKey: String) -> URL {
        rootDirectory.appendingPathComponent(dayKey, isDirectory: false)
            .appendingPathExtension("timelinelabels")
    }

    private func quarantineCorruptFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let quarantineURL = uniqueQuarantineURL(for: url)
        try fileManager.moveItem(at: url, to: quarantineURL)
    }

    private func uniqueQuarantineURL(for url: URL) -> URL {
        let timestamp = Int(Date().timeIntervalSince1970)
        var candidate = url.appendingPathExtension("corrupt-\(timestamp)")
        var suffix = 1

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url.appendingPathExtension("corrupt-\(timestamp)-\(suffix)")
            suffix += 1
        }

        return candidate
    }

    private func persistedDayKeys() throws -> Set<String> {
        var keys = Set(buckets.keys)
        let urls = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        for url in urls where url.pathExtension == "timelinelabels" {
            keys.insert(url.deletingPathExtension().lastPathComponent)
        }

        return keys
    }

    private static func sorted(_ segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }
            return $0.startDate < $1.startDate
        }
    }

}
