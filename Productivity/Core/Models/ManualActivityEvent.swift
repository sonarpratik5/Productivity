import Foundation
import UserNotifications

enum ManualActivityRecurrence: String, CaseIterable, Identifiable, Codable {
    case none
    case daily
    case weekdays
    case weekly
    case customWeekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Once"
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        case .customWeekly: "Custom"
        }
    }
}

enum ManualActivityAlert: String, CaseIterable, Identifiable, Codable {
    case none
    case atStart
    case fiveMinutesBefore
    case tenMinutesBefore
    case fifteenMinutesBefore
    case thirtyMinutesBefore
    case oneHourBefore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .atStart: "At start"
        case .fiveMinutesBefore: "5 minutes before"
        case .tenMinutesBefore: "10 minutes before"
        case .fifteenMinutesBefore: "15 minutes before"
        case .thirtyMinutesBefore: "30 minutes before"
        case .oneHourBefore: "1 hour before"
        }
    }

    var offset: TimeInterval? {
        switch self {
        case .none: nil
        case .atStart: 0
        case .fiveMinutesBefore: 5 * 60
        case .tenMinutesBefore: 10 * 60
        case .fifteenMinutesBefore: 15 * 60
        case .thirtyMinutesBefore: 30 * 60
        case .oneHourBefore: 60 * 60
        }
    }
}

struct ManualActivityEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var label: ActivityLabel
    var isSleep: Bool
    var recurrence: ManualActivityRecurrence
    var alert: ManualActivityAlert
    var weekdayMask: Set<Int>

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        label: ActivityLabel,
        isSleep: Bool = false,
        recurrence: ManualActivityRecurrence,
        alert: ManualActivityAlert = .none,
        weekdayMask: Set<Int> = []
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.label = label
        self.isSleep = isSleep
        self.recurrence = recurrence
        self.alert = alert
        self.weekdayMask = weekdayMask
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startDate
        case endDate
        case label
        case isSleep
        case recurrence
        case alert
        case weekdayMask
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        label = try container.decode(ActivityLabel.self, forKey: .label)
        isSleep = try container.decodeIfPresent(Bool.self, forKey: .isSleep)
            ?? title.localizedCaseInsensitiveContains("sleep")
        recurrence = try container.decode(ManualActivityRecurrence.self, forKey: .recurrence)
        alert = try container.decodeIfPresent(ManualActivityAlert.self, forKey: .alert) ?? .none
        weekdayMask = try container.decodeIfPresent(Set<Int>.self, forKey: .weekdayMask) ?? []
    }

    var category: ActivityCategory {
        label.category
    }

    var productivityScore: Double {
        label.productivityScore
    }

    func segments(in interval: DateInterval, calendar: Calendar = .current) -> [ActivitySegment] {
        switch recurrence {
        case .none:
            let normalizedEndDate = normalizedEndDate(for: startDate, calendar: calendar)
            let eventInterval = DateInterval(start: startDate, end: normalizedEndDate)
            guard interval.intersects(eventInterval) else { return [] }
            return [segment(id: id, startDate: max(startDate, interval.start), endDate: min(normalizedEndDate, interval.end))]

        case .daily, .weekdays, .weekly, .customWeekly:
            return recurringSegments(in: interval, calendar: calendar)
        }
    }

    func upcomingNotificationDates(from now: Date = Date(), calendar: Calendar = .current, limit: Int = 32) -> [Date] {
        guard let offset = alert.offset else { return [] }
        let horizonEnd = calendar.date(byAdding: .day, value: 60, to: now) ?? now.addingTimeInterval(60 * 24 * 60 * 60)
        let horizon = DateInterval(start: now.addingTimeInterval(-duration), end: horizonEnd)

        return Array(occurrenceStartDates(in: horizon, calendar: calendar)
            .compactMap { date -> Date? in
                let alertDate = date.addingTimeInterval(-offset)
                return alertDate > now ? alertDate : nil
            }
            .prefix(limit))
    }

    private func segment(id: UUID, startDate: Date, endDate: Date) -> ActivitySegment {
        ActivitySegment(
            id: id,
            appName: title,
            bundleIdentifier: isSleep ? "manual.event.sleep.\(id.uuidString)" : "manual.event.\(id.uuidString)",
            title: title,
            userDescription: isSleep ? "\(recurrence.title) sleep event" : "\(recurrence.title) manual event",
            startDate: startDate,
            endDate: endDate,
            category: category,
            label: label,
            productivityScore: productivityScore
        )
    }

    private var duration: TimeInterval {
        if endDate > startDate {
            return max(60, endDate.timeIntervalSince(startDate))
        }

        return max(60, endDate.addingTimeInterval(24 * 60 * 60).timeIntervalSince(startDate))
    }

    private func normalizedEndDate(for start: Date, calendar: Calendar) -> Date {
        let startComponents = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        let endComponents = calendar.dateComponents([.hour, .minute, .second], from: endDate)
        let startSeconds = seconds(from: startComponents)
        let endSeconds = seconds(from: endComponents)
        let dayEnd = calendar.date(bySettingHour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0, second: endComponents.second ?? 0, of: start)
            ?? start.addingTimeInterval(60)

        if endSeconds > startSeconds {
            return max(dayEnd, start.addingTimeInterval(60))
        }

        return max(calendar.date(byAdding: .day, value: 1, to: dayEnd) ?? dayEnd.addingTimeInterval(24 * 60 * 60), start.addingTimeInterval(60))
    }

    private func recurringSegments(in interval: DateInterval, calendar: Calendar) -> [ActivitySegment] {
        occurrenceStartDates(in: interval, calendar: calendar).compactMap { occurrenceStart in
            let occurrenceEnd = normalizedEndDate(for: occurrenceStart, calendar: calendar)
            let occurrenceInterval = DateInterval(start: occurrenceStart, end: occurrenceEnd)
            guard interval.intersects(occurrenceInterval) else { return nil }
            return segment(
                id: occurrenceID(for: occurrenceStart, calendar: calendar),
                startDate: max(occurrenceStart, interval.start),
                endDate: min(occurrenceEnd, interval.end)
            )
        }
    }

    private func occurrenceStartDates(in interval: DateInterval, calendar: Calendar) -> [Date] {
        let searchStart = calendar.date(byAdding: .day, value: -1, to: interval.start) ?? interval.start
        let searchEnd = calendar.date(byAdding: .day, value: 1, to: interval.end) ?? interval.end
        var day = calendar.startOfDay(for: searchStart)
        let template = calendar.dateComponents([.hour, .minute, .second], from: startDate)
        var dates: [Date] = []

        while day <= searchEnd {
            if occurs(on: day, calendar: calendar),
               let occurrenceStart = calendar.date(
                bySettingHour: template.hour ?? 0,
                minute: template.minute ?? 0,
                second: template.second ?? 0,
                of: day
               ) {
                dates.append(occurrenceStart)
            }

            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        return dates
    }

    private func occurs(on day: Date, calendar: Calendar) -> Bool {
        switch recurrence {
        case .none:
            calendar.isDate(day, inSameDayAs: startDate)
        case .daily:
            true
        case .weekdays:
            (2...6).contains(calendar.component(.weekday, from: day))
        case .weekly:
            calendar.component(.weekday, from: day) == calendar.component(.weekday, from: startDate)
        case .customWeekly:
            weekdayMask.contains(calendar.component(.weekday, from: day))
        }
    }

    private func seconds(from components: DateComponents) -> Int {
        ((components.hour ?? 0) * 60 * 60) + ((components.minute ?? 0) * 60) + (components.second ?? 0)
    }

    private func occurrenceID(for date: Date, calendar: Calendar) -> UUID {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let seed = "\(id.uuidString)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        var hash1: UInt64 = 0xcbf29ce484222325
        var hash2: UInt64 = 0x84222325cbf29ce4

        for byte in seed.utf8 {
            hash1 ^= UInt64(byte)
            hash1 &*= 0x100000001b3
            hash2 ^= UInt64(byte) &+ 0x9e3779b97f4a7c15
            hash2 &*= 0x100000001b3
        }

        let bytes: uuid_t = (
            UInt8((hash1 >> 56) & 0xff),
            UInt8((hash1 >> 48) & 0xff),
            UInt8((hash1 >> 40) & 0xff),
            UInt8((hash1 >> 32) & 0xff),
            UInt8((hash1 >> 24) & 0xff),
            UInt8((hash1 >> 16) & 0xff),
            UInt8((hash1 >> 8) & 0xff),
            UInt8(hash1 & 0xff),
            UInt8((hash2 >> 56) & 0xff),
            UInt8((hash2 >> 48) & 0xff),
            UInt8((hash2 >> 40) & 0xff),
            UInt8((hash2 >> 32) & 0xff),
            UInt8((hash2 >> 24) & 0xff),
            UInt8((hash2 >> 16) & 0xff),
            UInt8((hash2 >> 8) & 0xff),
            UInt8(hash2 & 0xff)
        )
        return UUID(uuid: bytes)
    }
}

enum ManualActivityEventStore {
    static let storageKey = "manual.activity.events"

    static func load() -> [ManualActivityEvent] {
        let decoder = PropertyListDecoder()
        if let data = try? Data(contentsOf: storageURL),
           let events = try? decoder.decode([ManualActivityEvent].self, from: data) {
            return events
        }

        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([ManualActivityEvent].self, from: data) else {
            return []
        }

        save(events)
        return events
    }

    static func save(_ events: [ManualActivityEvent]) {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(events)
            try data.write(to: storageURL, options: [.atomic])
            UserDefaults.standard.removeObject(forKey: storageKey)
        } catch {}
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        try? FileManager.default.removeItem(at: storageURL)
    }

    private static var storageURL: URL {
        let baseDirectory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        return (baseDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("ManualActivityEvents", isDirectory: true)
            .appendingPathComponent("events", isDirectory: false)
            .appendingPathExtension("manualevents")
    }
}

enum ManualActivityEventNotificationScheduler {
    private static let identifierPrefix = "manual.activity.event."
    // Shared cap used by both the scheduler and removeNotifications so the two
    // sides always cover the same identifier range without manual coordination.
    static let scheduleLimit = 32

    enum ScheduleResult {
        case scheduled(count: Int)
        case permissionDenied
        case noUpcomingDates
    }

    @discardableResult
    static func reschedule(_ event: ManualActivityEvent) async -> ScheduleResult {
        removeNotifications(for: event.id)
        guard event.alert != .none else { return .noUpcomingDates }

        // Compute upcoming dates synchronously first — pure CPU work — so we
        // skip the async permission check entirely when there is nothing to schedule
        // (e.g. a one-time event whose start time is already in the past).
        let upcomingDates = event.upcomingNotificationDates(limit: scheduleLimit)
        guard !upcomingDates.isEmpty else { return .noUpcomingDates }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            break
        case .denied:
            return .permissionDenied
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { return .permissionDenied }
            } catch {
                return .permissionDenied
            }
        @unknown default:
            return .permissionDenied
        }

        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.alert.title
        content.sound = .default

        var scheduledCount = 0
        for (index, date) in upcomingDates.enumerated() {
            let timeInterval = date.timeIntervalSinceNow
            guard timeInterval > 0 else { continue }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)
            let request = UNNotificationRequest(
                identifier: notificationIdentifier(eventID: event.id, index: index),
                content: content,
                trigger: trigger
            )
            if (try? await center.add(request)) != nil {
                scheduledCount += 1
            }
        }

        return scheduledCount > 0 ? .scheduled(count: scheduledCount) : .noUpcomingDates
    }

    static func removeNotifications(for eventID: UUID) {
        let prefix = notificationIdentifierPrefix(eventID: eventID)
        // Identifiers follow the deterministic "{prefix}.{index}" pattern up to
        // scheduleLimit, so constructing them directly avoids an async round-trip
        // to fetch all pending notification requests on every reschedule or delete.
        let identifiers = (0..<scheduleLimit).map { "\(prefix).\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func notificationIdentifier(eventID: UUID, index: Int) -> String {
        "\(notificationIdentifierPrefix(eventID: eventID)).\(index)"
    }

    private static func notificationIdentifierPrefix(eventID: UUID) -> String {
        "\(identifierPrefix)\(eventID.uuidString)"
    }

}
