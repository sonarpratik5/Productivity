import Foundation

struct AdvancedAnalyticsEngine {
    func snapshot(
        from segments: [ActivitySegment],
        range: AnalyticsRange,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> AnalyticsSnapshot {
        let interval = range.interval(endingAt: referenceDate, calendar: calendar)
        let clippedSegments = segments
            .filter { !$0.isLifecycleContext && !$0.isSleepEvent }
            .compactMap { clip($0, to: interval) }
        let primarySegments = ActivitySegment.primaryAttentionSegments(from: clippedSegments)
        let productiveIntervals = mergedIntervals(
            from: primarySegments.filter { $0.label.commonRollup == .productive }
        )
        var hourlyBuckets = makeHourlyBuckets()
        var dailyBuckets = makeDailyBuckets(in: interval, calendar: calendar)
        var appBuckets = [String: AnalyticsAppBucket]()
        var labelBuckets = [ActivityLabel: TimeInterval]()
        var totalTrackedTime: TimeInterval = 0
        var productiveTime: TimeInterval = 0
        var unproductiveTime: TimeInterval = 0
        var contextSwitchCount = 0
        var recoverySamples: [TimeInterval] = []
        var previousSegment: ActivitySegment?
        var pendingUnproductiveEnd: Date?

        for segment in primarySegments {
            let label = segment.label.commonRollup
            totalTrackedTime += segment.duration
            labelBuckets[segment.label, default: 0] += segment.duration
            if label == .productive {
                productiveTime += segment.duration
            } else if label == .unproductive {
                unproductiveTime += segment.duration
            }

            var appBucket = appBuckets[segment.bundleIdentifier] ?? AnalyticsAppBucket(
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier
            )
            appBucket.trackedDuration += segment.duration
            appBucket.weightedScore += segment.productivityScore * segment.duration
            appBucket.segmentCount += 1
            if label == .productive {
                appBucket.productiveDuration += segment.duration
            }
            appBuckets[segment.bundleIdentifier] = appBucket

            if let previousSegment,
               previousSegment.bundleIdentifier != segment.bundleIdentifier,
               segment.startDate >= previousSegment.endDate {
                contextSwitchCount += 1
            }

            if label == .unproductive {
                pendingUnproductiveEnd = segment.endDate
            } else if label == .productive,
                      let recoveryStart = pendingUnproductiveEnd,
                      segment.startDate >= recoveryStart {
                recoverySamples.append(segment.startDate.timeIntervalSince(recoveryStart))
                pendingUnproductiveEnd = nil
            }

            previousSegment = segment

            accumulateByHour(segment, buckets: &hourlyBuckets, calendar: calendar)
            accumulateByDay(segment, buckets: &dailyBuckets, calendar: calendar)
        }

        for productiveInterval in productiveIntervals {
            let day = calendar.startOfDay(for: productiveInterval.start)
            if var bucket = dailyBuckets[day] {
                bucket.focusStreaks.append(productiveInterval.duration)
                dailyBuckets[day] = bucket
            }
        }

        let hourlyItems = finalizedHourlyItems(from: hourlyBuckets)
        let dailyItems = finalizedDailyItems(from: dailyBuckets)
        let topApps = finalizedAppItems(from: appBuckets)
        let peakHour = rankedHour(in: hourlyItems, best: true)
        let weakestHour = rankedHour(in: hourlyItems, best: false)

        return AnalyticsSnapshot(
            range: range,
            interval: interval,
            activeDayCount: dailyItems.filter { $0.trackedDuration > 0 }.count,
            totalTrackedTime: totalTrackedTime,
            productiveTime: productiveTime,
            unproductiveTime: unproductiveTime,
            productiveRatio: totalTrackedTime > 0 ? productiveTime / totalTrackedTime : 0,
            averageFocusStreak: average(of: productiveIntervals.map(\.duration)),
            longestFocusStreak: productiveIntervals.map(\.duration).max() ?? 0,
            contextSwitchCount: contextSwitchCount,
            contextSwitchesPerHour: totalTrackedTime > 0
                ? Double(contextSwitchCount) / (totalTrackedTime / 3600)
                : 0,
            medianRecoveryTime: median(of: recoverySamples),
            peakFocusHour: peakHour,
            weakestFocusHour: weakestHour,
            dailyItems: dailyItems,
            hourlyItems: hourlyItems,
            topApps: Array(topApps.prefix(5)),
            labelBreakdown: labelBuckets
        )
    }

    private func accumulateByHour(
        _ segment: ActivitySegment,
        buckets: inout [AnalyticsHourBucket],
        calendar: Calendar
    ) {
        guard let segmentInterval = segment.safeInterval else { return }
        let label = segment.label.commonRollup
        var cursor = segmentInterval.start

        while cursor < segmentInterval.end {
            guard let hourInterval = calendar.dateInterval(of: .hour, for: cursor) else { break }
            let chunkEnd = min(segmentInterval.end, hourInterval.end)
            let duration = chunkEnd.timeIntervalSince(cursor)
            guard duration > 0 else { break }
            let hour = calendar.component(.hour, from: cursor)
            guard buckets.indices.contains(hour) else { break }
            buckets[hour].trackedDuration += duration
            buckets[hour].weightedScore += segment.productivityScore * duration
            if label == .productive {
                buckets[hour].productiveDuration += duration
            }
            cursor = chunkEnd
        }
    }

    private func accumulateByDay(
        _ segment: ActivitySegment,
        buckets: inout [Date: AnalyticsDayBucket],
        calendar: Calendar
    ) {
        guard let segmentInterval = segment.safeInterval else { return }
        let label = segment.label.commonRollup
        var cursor = segmentInterval.start

        while cursor < segmentInterval.end {
            let day = calendar.startOfDay(for: cursor)
            guard let dayInterval = calendar.dateInterval(of: .day, for: day) else { break }
            let chunkEnd = min(segmentInterval.end, dayInterval.end)
            let duration = chunkEnd.timeIntervalSince(cursor)
            guard duration > 0 else { break }
            var bucket = buckets[day] ?? AnalyticsDayBucket(dayStart: day)
            bucket.trackedDuration += duration
            bucket.weightedScore += segment.productivityScore * duration
            if label == .productive {
                bucket.productiveDuration += duration
            }
            buckets[day] = bucket
            cursor = chunkEnd
        }
    }

    private func makeHourlyBuckets() -> [AnalyticsHourBucket] {
        (0..<24).map { AnalyticsHourBucket(hour: $0) }
    }

    private func makeDailyBuckets(in interval: DateInterval, calendar: Calendar) -> [Date: AnalyticsDayBucket] {
        var buckets: [Date: AnalyticsDayBucket] = [:]
        var cursor = calendar.startOfDay(for: interval.start)
        let end = calendar.startOfDay(for: interval.end)

        while cursor <= end {
            buckets[cursor] = AnalyticsDayBucket(dayStart: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = nextDay
        }

        return buckets
    }

    private func finalizedHourlyItems(from buckets: [AnalyticsHourBucket]) -> [AnalyticsHourItem] {
        buckets.map { bucket in
            AnalyticsHourItem(
                hour: bucket.hour,
                trackedDuration: bucket.trackedDuration,
                productiveDuration: bucket.productiveDuration,
                productiveRatio: bucket.trackedDuration > 0 ? bucket.productiveDuration / bucket.trackedDuration : 0,
                averageScore: bucket.trackedDuration > 0 ? bucket.weightedScore / bucket.trackedDuration : 0
            )
        }
    }

    private func finalizedDailyItems(from buckets: [Date: AnalyticsDayBucket]) -> [AnalyticsDayItem] {
        buckets.values
            .sorted { $0.dayStart < $1.dayStart }
            .map { bucket in
                AnalyticsDayItem(
                    date: bucket.dayStart,
                    trackedDuration: bucket.trackedDuration,
                    productiveDuration: bucket.productiveDuration,
                    productiveRatio: bucket.trackedDuration > 0 ? bucket.productiveDuration / bucket.trackedDuration : 0,
                    averageScore: bucket.trackedDuration > 0 ? bucket.weightedScore / bucket.trackedDuration : 0,
                    averageFocusStreak: average(of: bucket.focusStreaks)
                )
            }
    }

    private func finalizedAppItems(from buckets: [String: AnalyticsAppBucket]) -> [AnalyticsAppItem] {
        buckets.values
            .map { bucket in
                AnalyticsAppItem(
                    appName: bucket.appName,
                    bundleIdentifier: bucket.bundleIdentifier,
                    trackedDuration: bucket.trackedDuration,
                    productiveRatio: bucket.trackedDuration > 0 ? bucket.productiveDuration / bucket.trackedDuration : 0,
                    averageScore: bucket.trackedDuration > 0 ? bucket.weightedScore / bucket.trackedDuration : 0,
                    averageSegmentDuration: bucket.segmentCount > 0
                        ? bucket.trackedDuration / Double(bucket.segmentCount)
                        : 0
                )
            }
            .sorted {
                if $0.trackedDuration == $1.trackedDuration {
                    return $0.averageScore > $1.averageScore
                }
                return $0.trackedDuration > $1.trackedDuration
            }
    }

    private func rankedHour(in items: [AnalyticsHourItem], best: Bool) -> AnalyticsHourItem? {
        items.reduce(nil) { selected, item in
            guard item.trackedDuration >= 20 * 60 else { return selected }
            guard let selected else { return item }

            if item.productiveRatio == selected.productiveRatio {
                if best {
                    return item.trackedDuration > selected.trackedDuration ? item : selected
                }
                return item.trackedDuration < selected.trackedDuration ? item : selected
            }

            if best {
                return item.productiveRatio > selected.productiveRatio ? item : selected
            }
            return item.productiveRatio < selected.productiveRatio ? item : selected
        }
    }

    private func mergedIntervals(from segments: [ActivitySegment]) -> [DateInterval] {
        let intervals = segments.compactMap(\.safeInterval).sorted { $0.start < $1.start }
        guard let firstInterval = intervals.first else { return [] }
        var merged = [firstInterval]

        for interval in intervals.dropFirst() {
            guard let last = merged.last else { continue }
            if interval.start <= last.end {
                merged.removeLast()
                merged.append(DateInterval(start: last.start, end: max(last.end, interval.end)))
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    private func average(of values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func median(of values: [TimeInterval]) -> TimeInterval {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func clip(_ segment: ActivitySegment, to interval: DateInterval) -> ActivitySegment? {
        guard let segmentInterval = segment.safeInterval, interval.intersects(segmentInterval) else { return nil }
        let startDate = max(segment.startDate, interval.start)
        let endDate = min(segment.endDate, interval.end)
        guard endDate > startDate else { return nil }
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
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case last14Days
    case last30Days
    case last90Days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last14Days: "14 days"
        case .last30Days: "30 days"
        case .last90Days: "90 days"
        }
    }

    private var dayCount: Int {
        switch self {
        case .last14Days: 14
        case .last30Days: 30
        case .last90Days: 90
        }
    }

    func interval(endingAt date: Date, calendar: Calendar) -> DateInterval {
        let end = date
        let dayStart = calendar.startOfDay(for: end)
        let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: dayStart) ?? dayStart
        return DateInterval(start: start, end: end)
    }
}

struct AnalyticsSnapshot {
    let range: AnalyticsRange
    let interval: DateInterval
    let activeDayCount: Int
    let totalTrackedTime: TimeInterval
    let productiveTime: TimeInterval
    let unproductiveTime: TimeInterval
    let productiveRatio: Double
    let averageFocusStreak: TimeInterval
    let longestFocusStreak: TimeInterval
    let contextSwitchCount: Int
    let contextSwitchesPerHour: Double
    let medianRecoveryTime: TimeInterval
    let peakFocusHour: AnalyticsHourItem?
    let weakestFocusHour: AnalyticsHourItem?
    let dailyItems: [AnalyticsDayItem]
    let hourlyItems: [AnalyticsHourItem]
    let topApps: [AnalyticsAppItem]
    let labelBreakdown: [ActivityLabel: TimeInterval]
}

struct AnalyticsHourItem: Identifiable {
    let hour: Int
    let trackedDuration: TimeInterval
    let productiveDuration: TimeInterval
    let productiveRatio: Double
    let averageScore: Double

    var id: Int { hour }
}

struct AnalyticsDayItem: Identifiable {
    let date: Date
    let trackedDuration: TimeInterval
    let productiveDuration: TimeInterval
    let productiveRatio: Double
    let averageScore: Double
    let averageFocusStreak: TimeInterval

    var id: Date { date }
}

struct AnalyticsAppItem: Identifiable {
    let appName: String
    let bundleIdentifier: String
    let trackedDuration: TimeInterval
    let productiveRatio: Double
    let averageScore: Double
    let averageSegmentDuration: TimeInterval

    var id: String { bundleIdentifier }
}

private struct AnalyticsHourBucket {
    let hour: Int
    var trackedDuration: TimeInterval = 0
    var productiveDuration: TimeInterval = 0
    var weightedScore: Double = 0
}

private struct AnalyticsDayBucket {
    let dayStart: Date
    var trackedDuration: TimeInterval = 0
    var productiveDuration: TimeInterval = 0
    var weightedScore: Double = 0
    var focusStreaks: [TimeInterval] = []
}

private struct AnalyticsAppBucket {
    let appName: String
    let bundleIdentifier: String
    var trackedDuration: TimeInterval = 0
    var productiveDuration: TimeInterval = 0
    var weightedScore: Double = 0
    var segmentCount: Int = 0
}
