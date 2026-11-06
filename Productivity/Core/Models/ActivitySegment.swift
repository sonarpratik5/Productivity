import Foundation

struct ActivitySegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let title: String
    let userDescription: String?
    let startDate: Date
    let endDate: Date
    let category: ActivityCategory
    let label: ActivityLabel
    let productivityScore: Double

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        title: String,
        userDescription: String? = nil,
        startDate: Date,
        endDate: Date,
        category: ActivityCategory,
        label: ActivityLabel? = nil,
        productivityScore: Double
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.userDescription = userDescription
        self.startDate = startDate
        self.endDate = endDate
        let resolvedLabel = label ?? ActivityLabel.from(category: category)
        self.category = label == nil ? category : resolvedLabel.category
        self.label = resolvedLabel
        self.productivityScore = productivityScore
    }

    enum CodingKeys: String, CodingKey {
        case id
        case appName
        case bundleIdentifier
        case title
        case userDescription
        case startDate
        case endDate
        case category
        case label
        case productivityScore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        appName = try container.decode(String.self, forKey: .appName)
        bundleIdentifier = try container.decode(String.self, forKey: .bundleIdentifier)
        title = try container.decode(String.self, forKey: .title)
        userDescription = try container.decodeIfPresent(String.self, forKey: .userDescription)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        category = try container.decode(ActivityCategory.self, forKey: .category)
        label = try container.decodeIfPresent(ActivityLabel.self, forKey: .label) ?? ActivityLabel.from(category: category)
        productivityScore = try container.decode(Double.self, forKey: .productivityScore)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(appName, forKey: .appName)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(userDescription, forKey: .userDescription)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(category, forKey: .category)
        try container.encode(label, forKey: .label)
        try container.encode(productivityScore, forKey: .productivityScore)
    }

    nonisolated var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    nonisolated var interval: DateInterval {
        safeInterval ?? DateInterval(start: startDate, duration: 0)
    }

    nonisolated var safeInterval: DateInterval? {
        guard endDate > startDate else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    var displayContext: String {
        guard let userDescription, !userDescription.isEmpty else {
            return "No context added"
        }

        return userDescription
    }

    var isCompanionContext: Bool {
        guard let userDescription else {
            return false
        }

        return userDescription.contains("Background companion activity")
            || userDescription.contains("Visible companion activity")
    }

    var isLifecycleContext: Bool {
        bundleIdentifier.hasPrefix("productivity.lifecycle.")
    }

    var isAppLifecycleAvailabilityContext: Bool {
        bundleIdentifier == "productivity.lifecycle.opened"
            || bundleIdentifier == "productivity.lifecycle.closed"
    }

    var isManualEventContext: Bool {
        bundleIdentifier.hasPrefix("manual.event.")
    }

    var isSleepEvent: Bool {
        isManualSleepEvent || bundleIdentifier == "productivity.lifecycle.sleep"
    }

    var isManualSleepEvent: Bool {
        bundleIdentifier.hasPrefix("manual.event.sleep.")
    }

    var isDayProgressEvent: Bool {
        isManualEventContext
    }

    var isDayProgressDisplayEvent: Bool {
        isDayProgressEvent && !isManualSleepEvent
    }

    var isDayProgressSleepBoundary: Bool {
        isManualSleepEvent && duration >= 10 * 60
    }

    static func primaryAttentionSegments(from segments: [ActivitySegment]) -> [ActivitySegment] {
        let sortedSegments = segments
            .filter { !$0.isCompanionContext && !$0.isLifecycleContext && $0.duration > 0 }
            .sorted {
                if $0.startDate == $1.startDate {
                    if $0.productivityScore == $1.productivityScore {
                        if $0.endDate == $1.endDate {
                            return $0.id.uuidString < $1.id.uuidString
                        }

                        return $0.endDate > $1.endDate
                    }

                    return $0.productivityScore > $1.productivityScore
                }

                return $0.startDate < $1.startDate
            }

        let events = sortedSegments.enumerated().flatMap { index, segment in
            [
                PrimaryAttentionEvent(key: index, date: segment.startDate, segment: segment, isStart: true),
                PrimaryAttentionEvent(key: index, date: segment.endDate, segment: segment, isStart: false)
            ]
        }
        .sorted { lhs, rhs in
            if lhs.date == rhs.date {
                if lhs.isStart == rhs.isStart {
                    return lhs.key < rhs.key
                }

                return !lhs.isStart && rhs.isStart
            }

            return lhs.date < rhs.date
        }

        guard let firstEvent = events.first else { return [] }

        var activeSegments: [Int: ActivitySegment] = [:]
        var previousDate = firstEvent.date
        var primarySegments: [ActivitySegment] = []
        var index = 0

        while index < events.count {
            let date = events[index].date

            if date > previousDate,
               let dominantSegment = activeSegments.values.max(by: comparePrimaryAttentionPriority) {
                appendPrimarySegment(
                    derivedFrom: dominantSegment,
                    startDate: previousDate,
                    endDate: date,
                    to: &primarySegments
                )
            }

            while index < events.count && events[index].date == date {
                let event = events[index]
                if event.isStart {
                    activeSegments[event.key] = event.segment
                } else {
                    activeSegments.removeValue(forKey: event.key)
                }
                index += 1
            }

            previousDate = date
        }

        return primarySegments
    }

    static func companionContextSegments(from segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.filter { $0.isCompanionContext && $0.duration > 0 }
    }

    private nonisolated static func comparePrimaryAttentionPriority(_ lhs: ActivitySegment, _ rhs: ActivitySegment) -> Bool {
        if lhs.productivityScore == rhs.productivityScore {
            if lhs.startDate == rhs.startDate {
                if lhs.endDate == rhs.endDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.endDate < rhs.endDate
            }

            return lhs.startDate > rhs.startDate
        }

        return lhs.productivityScore < rhs.productivityScore
    }

    private static func appendPrimarySegment(
        derivedFrom segment: ActivitySegment,
        startDate: Date,
        endDate: Date,
        to segments: inout [ActivitySegment]
    ) {
        guard endDate > startDate else { return }

        if let lastSegment = segments.last,
           lastSegment.id == segment.id,
           lastSegment.endDate == startDate {
            segments.removeLast()
            segments.append(ActivitySegment(
                id: segment.id,
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                title: segment.title,
                userDescription: segment.userDescription,
                startDate: lastSegment.startDate,
                endDate: endDate,
                category: segment.category,
                label: segment.label,
                productivityScore: segment.productivityScore
            ))
            return
        }

        segments.append(ActivitySegment(
            id: segment.id,
            appName: segment.appName,
            bundleIdentifier: segment.bundleIdentifier,
            title: segment.title,
            userDescription: segment.userDescription,
            startDate: startDate,
            endDate: endDate,
            category: segment.category,
            label: segment.label,
            productivityScore: segment.productivityScore
        ))
    }
}

private struct PrimaryAttentionEvent {
    let key: Int
    let date: Date
    let segment: ActivitySegment
    let isStart: Bool
}
