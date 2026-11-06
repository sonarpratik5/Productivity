import Foundation

struct TimelineStream: Identifiable {
    let number: Int
    let segments: [ActivitySegment]

    var id: Int { number }

    static func packed(from segments: [ActivitySegment]) -> [TimelineStream] {
        let primarySegments = ActivitySegment.primaryAttentionSegments(from: segments)
        let lifecycleSegments = segments
            .filter { $0.isLifecycleContext && $0.duration > 0 }
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.endDate < $1.endDate
                }

                return $0.startDate < $1.startDate
            }
        let companionSegments = removeCompanionOverlaps(
            from: coalescedCompanionSegments(ActivitySegment.companionContextSegments(from: segments)),
            primarySegments: primarySegments
        )
        let orderedLanes = [primarySegments].filter { !$0.isEmpty }
            + [lifecycleSegments].filter { !$0.isEmpty }
            + Array(pack(companionSegments).sorted(by: compareCompanionLanes).prefix(2))

        return orderedLanes.enumerated().map { index, segments in
            TimelineStream(number: index + 1, segments: segments)
        }
    }

    private nonisolated static func pack(_ segments: [ActivitySegment]) -> [[ActivitySegment]] {
        let sortedSegments = segments.sorted {
            if $0.startDate == $1.startDate {
                if $0.productivityScore == $1.productivityScore {
                    if $0.endDate == $1.endDate {
                        return $0.id.uuidString < $1.id.uuidString
                    }

                    return $0.endDate < $1.endDate
                }

                return $0.productivityScore > $1.productivityScore
            }

            return $0.startDate < $1.startDate
        }

        var lanes: [[ActivitySegment]] = []
        var laneEndDates: [Date] = []

        for segment in sortedSegments {
            if let laneIndex = laneEndDates.firstIndex(where: { $0 <= segment.startDate }) {
                lanes[laneIndex].append(segment)
                laneEndDates[laneIndex] = segment.endDate
            } else {
                lanes.append([segment])
                laneEndDates.append(segment.endDate)
            }
        }

        return lanes
    }

    private nonisolated static func compareCompanionLanes(_ lhs: [ActivitySegment], _ rhs: [ActivitySegment]) -> Bool {
        let lhsDuration = lhs.reduce(0) { $0 + duration(of: $1) }
        let rhsDuration = rhs.reduce(0) { $0 + duration(of: $1) }
        if lhsDuration == rhsDuration {
            let lhsFirst = lhs.first
            let rhsFirst = rhs.first
            if lhsFirst?.startDate == rhsFirst?.startDate {
                return (lhsFirst?.id.uuidString ?? "") < (rhsFirst?.id.uuidString ?? "")
            }

            return (lhsFirst?.startDate ?? .distantFuture) < (rhsFirst?.startDate ?? .distantFuture)
        }

        return lhsDuration > rhsDuration
    }

    private static func removeCompanionOverlaps(
        from companionSegments: [ActivitySegment],
        primarySegments: [ActivitySegment]
    ) -> [ActivitySegment] {
        let primaryIntervalsByBundleIdentifier = Dictionary(
            grouping: primarySegments.compactMap { segment -> (String, DateInterval)? in
                guard let interval = segment.safeInterval else { return nil }
                return (segment.bundleIdentifier, interval)
            },
            by: \.0
        )
        .mapValues { entries in
            entries.map(\.1).sorted(by: { $0.start < $1.start })
        }

        return companionSegments.flatMap { companionSegment in
            guard let companionInterval = companionSegment.safeInterval else {
                return [ActivitySegment]()
            }

            let overlappingPrimaryIntervals = (primaryIntervalsByBundleIdentifier[companionSegment.bundleIdentifier] ?? [])
                .filter { $0.intersects(companionInterval) }

            return subtract(overlappingPrimaryIntervals, from: companionSegment)
        }
    }

    private static func coalescedCompanionSegments(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        Dictionary(grouping: segments, by: \.bundleIdentifier)
            .values
            .flatMap { coalesceOverlappingSegments($0) }
            .sorted {
                if $0.startDate == $1.startDate {
                    if $0.endDate == $1.endDate {
                        return $0.id.uuidString < $1.id.uuidString
                    }

                    return $0.endDate < $1.endDate
                }

                return $0.startDate < $1.startDate
            }
    }

    private static func coalesceOverlappingSegments(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        let sortedSegments = segments.sorted {
            if $0.startDate == $1.startDate {
                if $0.endDate == $1.endDate {
                    return $0.id.uuidString < $1.id.uuidString
                }

                return $0.endDate < $1.endDate
            }

            return $0.startDate < $1.startDate
        }

        var coalescedSegments: [ActivitySegment] = []
        for segment in sortedSegments {
            guard let lastSegment = coalescedSegments.last else {
                coalescedSegments.append(segment)
                continue
            }

            if lastSegment.endDate >= segment.startDate {
                coalescedSegments.removeLast()
                coalescedSegments.append(ActivitySegment(
                    id: lastSegment.id,
                    appName: lastSegment.appName,
                    bundleIdentifier: lastSegment.bundleIdentifier,
                    title: lastSegment.title,
                    userDescription: lastSegment.userDescription,
                    startDate: lastSegment.startDate,
                    endDate: max(lastSegment.endDate, segment.endDate),
                    category: lastSegment.category,
                    label: lastSegment.label,
                    productivityScore: lastSegment.productivityScore
                ))
            } else {
                coalescedSegments.append(segment)
            }
        }

        return coalescedSegments
    }

    private static func subtract(_ excludedIntervals: [DateInterval], from segment: ActivitySegment) -> [ActivitySegment] {
        guard let segmentInterval = segment.safeInterval else { return [] }
        var remainingIntervals = [segmentInterval]

        for excludedInterval in excludedIntervals.sorted(by: { $0.start < $1.start }) {
            remainingIntervals = remainingIntervals.flatMap { interval in
                subtract(excludedInterval, from: interval)
            }
            guard !remainingIntervals.isEmpty else { break }
        }

        return remainingIntervals.compactMap { interval in
            guard interval.duration > 0 else { return nil }
            return ActivitySegment(
                id: interval == segmentInterval ? segment.id : UUID(),
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                title: segment.title,
                userDescription: segment.userDescription,
                startDate: interval.start,
                endDate: interval.end,
                category: segment.category,
                label: segment.label,
                productivityScore: segment.productivityScore
            )
        }
    }

    private static func subtract(_ excludedInterval: DateInterval, from interval: DateInterval) -> [DateInterval] {
        guard interval.intersects(excludedInterval) else { return [interval] }

        var intervals: [DateInterval] = []
        if excludedInterval.start > interval.start {
            intervals.append(DateInterval(start: interval.start, end: min(excludedInterval.start, interval.end)))
        }

        if excludedInterval.end < interval.end {
            intervals.append(DateInterval(start: max(excludedInterval.end, interval.start), end: interval.end))
        }

        return intervals.filter { $0.duration > 0 }
    }

    private nonisolated static func duration(of segment: ActivitySegment) -> TimeInterval {
        max(0, segment.endDate.timeIntervalSince(segment.startDate))
    }
}

struct TimelineLabelSegment: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var label: ActivityLabel
    var startDate: Date
    var endDate: Date

    nonisolated init(id: UUID = UUID(), label: ActivityLabel, startDate: Date, endDate: Date) {
        self.id = id
        self.label = label
        self.startDate = startDate
        self.endDate = endDate
    }

    nonisolated var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }

    nonisolated static func normalized(_ segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        let sortedSegments = segments
            .filter { $0.duration > 0 }
            .sorted {
                if $0.startDate == $1.startDate {
                    if $0.endDate == $1.endDate {
                        return $0.id.uuidString < $1.id.uuidString
                    }

                    return $0.endDate < $1.endDate
                }

                return $0.startDate < $1.startDate
            }

        let events = sortedSegments.enumerated().flatMap { index, segment in
            [
                NormalizedTimelineLabelEvent(key: index, date: segment.startDate, segment: segment, isStart: true),
                NormalizedTimelineLabelEvent(key: index, date: segment.endDate, segment: segment, isStart: false)
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

        var activeSegments: [Int: TimelineLabelSegment] = [:]
        var previousDate = firstEvent.date
        var normalizedSegments: [TimelineLabelSegment] = []
        var index = 0

        while index < events.count {
            let date = events[index].date

            if date > previousDate,
               let activeEntry = activeSegments.max(by: { $0.key < $1.key }) {
                appendNormalizedLabelSegment(
                    activeEntry.value,
                    startDate: previousDate,
                    endDate: date,
                    to: &normalizedSegments
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

        return normalizedSegments
    }

    private nonisolated static func appendNormalizedLabelSegment(
        _ segment: TimelineLabelSegment,
        startDate: Date,
        endDate: Date,
        to normalizedSegments: inout [TimelineLabelSegment]
    ) {
        if let lastSegment = normalizedSegments.last,
           lastSegment.label.id == segment.label.id,
           lastSegment.endDate == startDate {
            normalizedSegments.removeLast()
            normalizedSegments.append(TimelineLabelSegment(
                id: lastSegment.id,
                label: segment.label,
                startDate: lastSegment.startDate,
                endDate: endDate
            ))
        } else {
            let existingIDs = Set(normalizedSegments.map(\.id))
            normalizedSegments.append(TimelineLabelSegment(
                id: normalizedSegmentID(
                    for: segment,
                    startDate: startDate,
                    endDate: endDate,
                    existingIDs: existingIDs
                ),
                label: segment.label,
                startDate: startDate,
                endDate: endDate
            ))
        }
    }

    private nonisolated static func normalizedSegmentID(
        for segment: TimelineLabelSegment,
        startDate: Date,
        endDate: Date,
        existingIDs: Set<UUID>
    ) -> UUID {
        guard existingIDs.contains(segment.id) else {
            return segment.id
        }

        var suffix = 1
        while true {
            let candidate = deterministicSplitID(
                sourceID: segment.id,
                labelID: segment.label.id,
                startDate: startDate,
                endDate: endDate,
                suffix: suffix
            )
            if !existingIDs.contains(candidate) {
                return candidate
            }
            suffix += 1
        }
    }

    private nonisolated static func deterministicSplitID(
        sourceID: UUID,
        labelID: String,
        startDate: Date,
        endDate: Date,
        suffix: Int
    ) -> UUID {
        let seed = [
            sourceID.uuidString,
            labelID,
            String(startDate.timeIntervalSinceReferenceDate.bitPattern),
            String(endDate.timeIntervalSinceReferenceDate.bitPattern),
            String(suffix)
        ].joined(separator: "|")
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

    static func derived(from segments: [ActivitySegment]) -> [TimelineLabelSegment] {
        let sourceSegments = ActivitySegment.primaryAttentionSegments(from: segments)
            .filter { !$0.isSleepEvent }
        let events = sourceSegments.enumerated().flatMap { index, segment in
            [
                TimelineLabelEvent(key: index, date: segment.startDate, segment: segment, isStart: true),
                TimelineLabelEvent(key: index, date: segment.endDate, segment: segment, isStart: false)
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
        var derivedSegments: [TimelineLabelSegment] = []
        var index = 0

        while index < events.count {
            let date = events[index].date

            if date > previousDate {
                let label = dominantLabel(from: Array(activeSegments.values), startDate: previousDate, endDate: date)
                appendLabelSegment(label, startDate: previousDate, endDate: date, to: &derivedSegments)
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

        return derivedSegments
    }

    private static func appendLabelSegment(
        _ label: ActivityLabel,
        startDate: Date,
        endDate: Date,
        to derivedSegments: inout [TimelineLabelSegment]
    ) {
        if let lastSegment = derivedSegments.last,
           lastSegment.label.id == label.id,
           lastSegment.endDate == startDate {
            derivedSegments.removeLast()
            derivedSegments.append(TimelineLabelSegment(
                label: label,
                startDate: lastSegment.startDate,
                endDate: endDate
            ))
        } else {
            derivedSegments.append(TimelineLabelSegment(label: label, startDate: startDate, endDate: endDate))
        }
    }

    private static func dominantLabel(from segments: [ActivitySegment], startDate: Date, endDate: Date) -> ActivityLabel {
        guard !segments.isEmpty else { return .unknown }

        let primarySegments = segments.filter { !$0.isCompanionContext }
        guard !primarySegments.isEmpty else {
            return .unproductive
        }

        var durationsByLabel: [ActivityLabel: TimeInterval] = [:]
        var highestScoreByLabel: [ActivityLabel: Double] = [:]
        var highestScoringSegment: ActivitySegment?

        for segment in primarySegments {
            let overlapStart = max(segment.startDate, startDate)
            let overlapEnd = min(segment.endDate, endDate)
            let overlapDuration = max(0, overlapEnd.timeIntervalSince(overlapStart))

            durationsByLabel[segment.label, default: 0] += overlapDuration
            highestScoreByLabel[segment.label] = max(
                highestScoreByLabel[segment.label] ?? 0,
                segment.productivityScore
            )

            if highestScoringSegment == nil || segment.productivityScore > (highestScoringSegment?.productivityScore ?? 0) {
                highestScoringSegment = segment
            }
        }

        let labelDurations = durationsByLabel.map { (label: $0.key, duration: $0.value) }
        let durations: [(label: ActivityLabel, duration: TimeInterval)] = [
            (.productive, ActivityLabel.rollupDuration(for: .productive, in: labelDurations)),
            (.unproductive, ActivityLabel.rollupDuration(for: .unproductive, in: labelDurations)),
            (.unknown, ActivityLabel.rollupDuration(for: .unknown, in: labelDurations))
        ]
        let longestDuration = durations.map(\.duration).max() ?? 0
        let strongestLabels = durations.filter { $0.duration == longestDuration }.map(\.label)

        if longestDuration == 0 || strongestLabels.count > 1 {
            return highestScoringSegment?.label ?? .unknown
        }

        guard let strongestRollup = strongestLabels.first else {
            return highestScoringSegment?.label ?? .unknown
        }

        return durationsByLabel
            .filter { $0.value > 0 && $0.key.commonRollup == strongestRollup.commonRollup }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    let lhsScore = highestScoreByLabel[lhs.key] ?? 0
                    let rhsScore = highestScoreByLabel[rhs.key] ?? 0
                    if lhsScore == rhsScore {
                        return lhs.key.id < rhs.key.id
                    }

                    return lhsScore > rhsScore
                }

                return lhs.value > rhs.value
            }
            .first?
            .key ?? strongestRollup
    }
}

private struct TimelineLabelEvent {
    let key: Int
    let date: Date
    let segment: ActivitySegment
    let isStart: Bool
}

private struct NormalizedTimelineLabelEvent {
    let key: Int
    let date: Date
    let segment: TimelineLabelSegment
    let isStart: Bool
}
