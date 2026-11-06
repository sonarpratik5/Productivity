import Foundation

protocol InsightGenerating {
    func dailyOverview(from segments: [ActivitySegment], on date: Date) -> DailyActivityOverview
    func summaries(from overview: DailyActivityOverview) -> [InsightSummary]
}

struct InsightEngine: InsightGenerating {
    func dailyOverview(from segments: [ActivitySegment], on date: Date = Date()) -> DailyActivityOverview {
        let calendar = Calendar.current
        let dayInterval = calendar.dateInterval(of: .day, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
        let elapsedInterval = DateInterval(
            start: dayInterval.start,
            end: min(max(date, dayInterval.start), dayInterval.end)
        )
        let daySegments = segments.compactMap { clippedSegment($0, to: dayInterval) }
        let elapsedDaySegments = daySegments.compactMap { clippedSegment($0, to: elapsedInterval) }
        let primaryAttentionSegments = plannedContextAwareSegments(from: sleepExcludedSegments(from: elapsedDaySegments))
        let rollup = labelDurationRollup(from: primaryAttentionSegments)

        return DailyActivityOverview(
            date: date,
            productiveTime: rollup.productive,
            unproductiveTime: rollup.unproductive,
            unknownTime: rollup.unknown,
            totalTrackedTime: rollup.total,
            segments: daySegments
        )
    }

    func summaries(from overview: DailyActivityOverview) -> [InsightSummary] {
        [
            InsightSummary(
                title: "Productive",
                value: DurationFormatting.abbreviated(overview.productiveTime),
                trend: "\(Int(overview.productivityRatio * 100))% of tracked time",
                category: .focus
            ),
            InsightSummary(
                title: "Unproductive",
                value: DurationFormatting.abbreviated(overview.unproductiveTime),
                trend: "Manually relabel when needed",
                category: .entertainment
            ),
            InsightSummary(
                title: "Unknown",
                value: DurationFormatting.abbreviated(overview.unknownTime),
                trend: "Apps still needing classification",
                category: .unknown
            )
        ]
    }

    private func clippedSegment(_ segment: ActivitySegment, to interval: DateInterval) -> ActivitySegment? {
        guard let segmentInterval = segment.safeInterval, interval.intersects(segmentInterval) else { return nil }
        let startDate = max(segment.startDate, interval.start)
        let endDate = min(segment.endDate, interval.end)
        guard endDate > startDate else { return nil }
        guard startDate != segment.startDate || endDate != segment.endDate else { return segment }

        return ActivitySegment(
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
        )
    }

    private func plannedContextAwareSegments(from segments: [ActivitySegment]) -> [ActivitySegment] {
        let plannedSegments = ActivitySegment.primaryAttentionSegments(from: segments.filter { $0.isManualEventContext })
        let plannedIntervals = plannedSegments.compactMap(\.safeInterval)
        let trackedSegments = ActivitySegment.primaryAttentionSegments(from: segments.filter { !$0.isManualEventContext })
        let remainingTrackedSegments = trackedSegments.flatMap { subtract(plannedIntervals, from: $0) }

        return ActivitySegment.primaryAttentionSegments(from: plannedSegments + remainingTrackedSegments)
    }

    private func sleepExcludedSegments(from segments: [ActivitySegment]) -> [ActivitySegment] {
        let sleepIntervals = segments
            .filter(\.isSleepEvent)
            .compactMap(\.safeInterval)
            .merged()

        guard !sleepIntervals.isEmpty else {
            return segments.filter { !$0.isSleepEvent }
        }

        return segments
            .filter { !$0.isSleepEvent }
            .flatMap { subtract(sleepIntervals, from: $0) }
    }

    private func labelDurationRollup(from segments: [ActivitySegment]) -> LabelDurationRollup {
        segments.reduce(into: LabelDurationRollup()) { rollup, segment in
            rollup.total += segment.duration

            switch segment.label.commonRollup {
            case .productive:
                rollup.productive += segment.duration
            case .unproductive:
                rollup.unproductive += segment.duration
            case .unknown:
                rollup.unknown += segment.duration
            default:
                rollup.unknown += segment.duration
            }
        }
    }

    private func subtract(_ excludedIntervals: [DateInterval], from segment: ActivitySegment) -> [ActivitySegment] {
        guard let segmentInterval = segment.safeInterval else { return [] }
        var remainingIntervals = [segmentInterval]

        for excludedInterval in excludedIntervals {
            remainingIntervals = remainingIntervals.flatMap { subtract(excludedInterval, from: $0) }
            guard !remainingIntervals.isEmpty else { break }
        }

        return remainingIntervals.map { interval in
            ActivitySegment(
                id: segment.id,
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

    private func subtract(_ excludedInterval: DateInterval, from interval: DateInterval) -> [DateInterval] {
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
}

private struct LabelDurationRollup {
    var productive: TimeInterval = 0
    var unproductive: TimeInterval = 0
    var unknown: TimeInterval = 0
    var total: TimeInterval = 0
}

private extension Array where Element == DateInterval {
    func merged() -> [DateInterval] {
        let sortedIntervals = sorted { $0.start < $1.start }
        var mergedIntervals: [DateInterval] = []

        for interval in sortedIntervals {
            guard let lastInterval = mergedIntervals.last else {
                mergedIntervals.append(interval)
                continue
            }

            if lastInterval.end >= interval.start {
                mergedIntervals.removeLast()
                mergedIntervals.append(DateInterval(
                    start: lastInterval.start,
                    end: Swift.max(lastInterval.end, interval.end)
                ))
            } else {
                mergedIntervals.append(interval)
            }
        }

        return mergedIntervals
    }
}
