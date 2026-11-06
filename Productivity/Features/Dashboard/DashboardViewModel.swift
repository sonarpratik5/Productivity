import Foundation
import Observation

enum ActivityTrackingStatus: Equatable {
    case paused
    case starting
    case tracking
    case waitingForTrackedApp
}

@MainActor
@Observable
final class DashboardViewModel {
    private let activityTracker: any ActivityTracking
    private let insightEngine: any InsightGenerating
    private let activityRepository: any ActivityRepository
    private let timelineLabelRepository: any TimelineLabelRepository

    var overview: DailyActivityOverview
    var trackingStatus: ActivityTrackingStatus = .paused
    var labelSegments: [TimelineLabelSegment] = []
    var isNotificationPermissionDenied: Bool = false
    var manualEvents: [ManualActivityEvent]
    var insightSegments: [ActivitySegment] = []
    var todayMetricSegments: [ActivitySegment] = []
    var insightMetricSegments: [ActivitySegment] = []
    @ObservationIgnored private var persistedSegments: [ActivitySegment]
    @ObservationIgnored private var liveSegments: [ActivitySegment]
    @ObservationIgnored private var lastRefreshedLiveSegments: [ActivitySegment]?
    @ObservationIgnored private var lastRefreshedLiveDayStart: Date?
    @ObservationIgnored private var lastPersistedLiveSegmentsByID: [UUID: ActivitySegment] = [:]
    @ObservationIgnored private var deletedSegmentIDs = Set<UUID>()
    @ObservationIgnored private var hasStartedTracking = false
    @ObservationIgnored private var hasLoadedPersistedSegments = false
    @ObservationIgnored private var requestedInsightIntervals: [DateInterval] = []

    init(
        activityTracker: any ActivityTracking,
        insightEngine: any InsightGenerating,
        activityRepository: any ActivityRepository,
        timelineLabelRepository: any TimelineLabelRepository,
        initialSegments: [ActivitySegment] = []
    ) {
        self.activityTracker = activityTracker
        self.insightEngine = insightEngine
        self.activityRepository = activityRepository
        self.timelineLabelRepository = timelineLabelRepository
        self.persistedSegments = initialSegments
        self.liveSegments = []
        let loadedManualEvents = ManualActivityEventStore.load()
        self.manualEvents = loadedManualEvents
        let todayInterval = Self.dayInterval(containing: Date())
        let initialStatsSegments = Self.sortedSegments(initialSegments + Self.manualSegments(from: loadedManualEvents, in: todayInterval))
        let initialOverview = insightEngine.dailyOverview(from: initialStatsSegments, on: Date())
        let overview = DailyActivityOverview(
            date: initialOverview.date,
            productiveTime: initialOverview.productiveTime,
            unproductiveTime: initialOverview.unproductiveTime,
            unknownTime: initialOverview.unknownTime,
            totalTrackedTime: initialOverview.totalTrackedTime,
            segments: initialStatsSegments
        )
        self.overview = overview
        self.todayMetricSegments = initialStatsSegments
        self.insightMetricSegments = initialStatsSegments
        self.insightSegments = initialStatsSegments
    }

    func startTracking(isEnabled: Bool = true) async {
        await loadPersistedSegmentsIfNeeded()
        guard !Task.isCancelled else { return }
        guard isEnabled else {
            await stopTracking(markAsPaused: true)
            return
        }
        guard !hasStartedTracking else { return }
        hasStartedTracking = true
        trackingStatus = .starting
        defer {
            if !Task.isCancelled && trackingStatus != .paused {
                trackingStatus = .paused
            }
            hasStartedTracking = false
        }
        guard !Task.isCancelled else { return }
        await activityTracker.start()
        if Task.isCancelled {
            await activityTracker.stop()
            return
        }

        for await segments in activityTracker.activitySegments {
            guard !Task.isCancelled else { break }
            let filteredLiveSegments = segments.filter { !deletedSegmentIDs.contains($0.id) }
            if shouldRefreshLiveViews(for: filteredLiveSegments, at: Date()) {
                liveSegments = filteredLiveSegments
                refreshActivityViews()
            } else {
                liveSegments = filteredLiveSegments
            }
            await persistLiveSegments()
            trackingStatus = activityTracker.isCapturingLiveActivity ? .tracking : .waitingForTrackedApp
        }
    }

    func stopTracking(markAsPaused: Bool = true) async {
        if markAsPaused {
            trackingStatus = .paused
        }
        hasStartedTracking = false
        await activityTracker.stop()
        liveSegments = activityTracker.currentSegments.filter { !deletedSegmentIDs.contains($0.id) }
        refreshActivityViews()
        await persistLiveSegments()
        try? await activityRepository.flush()
    }

    func loadPersistedSegmentsIfNeeded() async {
        guard !hasLoadedPersistedSegments else { return }
        hasLoadedPersistedSegments = true
        await reloadPersistedSegments()
    }

    func resetActivityState() {
        persistedSegments = []
        liveSegments = []
        lastRefreshedLiveSegments = nil
        lastRefreshedLiveDayStart = nil
        lastPersistedLiveSegmentsByID.removeAll()
        deletedSegmentIDs.removeAll()
        labelSegments = []
        manualEvents = []
        insightSegments = []
        todayMetricSegments = []
        insightMetricSegments = []
        requestedInsightIntervals = []
        hasLoadedPersistedSegments = false
        refreshActivityViews()
    }

    func reloadPersistedSegments() async {
        do {
            let insightLoadInterval = Self.insightLoadInterval(containing: Date())
            let loadIntervals = Self.mergedIntervals([insightLoadInterval] + requestedInsightIntervals)
            let loadedSegments = try await Self.loadSegments(
                from: activityRepository,
                in: loadIntervals
            )
            persistedSegments = Self.mergedTrackedSegments(loadedSegments)
                .filter { !deletedSegmentIDs.contains($0.id) }
            labelSegments = Self.mergedLabelSegments(try await Self.loadLabelSegments(
                from: timelineLabelRepository,
                in: loadIntervals
            ))
            manualEvents = Self.sortedManualEvents(ManualActivityEventStore.load())
            refreshActivityViews()
        } catch {
            // Keep the live UI usable if the local store cannot be read.
        }
    }

    func loadInsightData(for interval: DateInterval) async {
        guard interval.duration > 0 else { return }

        do {
            let loadedSegments = try await Self.loadSegments(
                from: activityRepository,
                in: [interval]
            )
                .filter { !deletedSegmentIDs.contains($0.id) }
            let loadedLabelSegments = try await Self.loadLabelSegments(
                from: timelineLabelRepository,
                in: [interval]
            )
            persistedSegments = Self.mergedTrackedSegments(persistedSegments + loadedSegments)
                .filter { !deletedSegmentIDs.contains($0.id) }
            labelSegments = Self.mergedLabelSegments(labelSegments + loadedLabelSegments)
            manualEvents = Self.sortedManualEvents(ManualActivityEventStore.load())
            requestedInsightIntervals = Self.mergedIntervals(requestedInsightIntervals + [interval])
            refreshActivityViews()
        } catch {
            // Keep the current insight snapshot available if a historical interval cannot be read.
        }
    }

    func deleteSegment(_ segment: ActivitySegment) async {
        deletedSegmentIDs.insert(segment.id)
        persistedSegments.removeAll { $0.id == segment.id }
        liveSegments.removeAll { $0.id == segment.id }

        let matchingManualEventIDs = manualEventIDs(matching: segment)
        if !matchingManualEventIDs.isEmpty {
            manualEvents.removeAll { matchingManualEventIDs.contains($0.id) }
            ManualActivityEventStore.save(manualEvents)
            for eventID in matchingManualEventIDs {
                ManualActivityEventNotificationScheduler.removeNotifications(for: eventID)
            }
        }

        do {
            try await activityRepository.deleteSegments(identifiedBy: [segment.id])
        } catch {
            // Keep the UI deletion applied; the persistent store can surface errors once real DB reporting exists.
        }

        refreshActivityViews()
    }

    func addManualEvent(_ event: ManualActivityEvent) {
        let normalizedEvent = Self.normalizedManualEventForToday(event)
        manualEvents.removeAll { $0.id == normalizedEvent.id }
        manualEvents.append(normalizedEvent)
        manualEvents = Self.sortedManualEvents(manualEvents)
        ManualActivityEventStore.save(manualEvents)
        Task {
            let result = await ManualActivityEventNotificationScheduler.reschedule(normalizedEvent)
            switch result {
            case .permissionDenied: isNotificationPermissionDenied = true
            case .scheduled: isNotificationPermissionDenied = false
            case .noUpcomingDates: break
            }
        }
        refreshActivityViews()
    }

    func updateManualEvent(_ event: ManualActivityEvent) {
        let normalizedEvent = Self.normalizedManualEventForToday(event)
        if let index = manualEvents.firstIndex(where: { $0.id == normalizedEvent.id }) {
            manualEvents[index] = normalizedEvent
        } else {
            manualEvents.append(normalizedEvent)
        }

        manualEvents = Self.sortedManualEvents(manualEvents)
        ManualActivityEventStore.save(manualEvents)
        Task {
            let result = await ManualActivityEventNotificationScheduler.reschedule(normalizedEvent)
            switch result {
            case .permissionDenied: isNotificationPermissionDenied = true
            case .scheduled: isNotificationPermissionDenied = false
            case .noUpcomingDates: break
            }
        }
        refreshActivityViews()
    }

    func deleteManualEvent(_ event: ManualActivityEvent) {
        manualEvents.removeAll { $0.id == event.id }
        ManualActivityEventStore.save(manualEvents)
        ManualActivityEventNotificationScheduler.removeNotifications(for: event.id)
        refreshActivityViews()
    }

    func updateLabelSegments(_ updatedLabelSegments: [TimelineLabelSegment]) {
        let todayInterval = Self.dayInterval(containing: Date())
        let clampedUpdatedSegments = TimelineLabelSegment.normalized(
            Self.clampedLabelSegments(updatedLabelSegments, to: todayInterval)
        )
        let retainedLabelSegments = labelSegments.flatMap { segment in
            Self.labelSegments(of: segment, outside: todayInterval)
        }
        labelSegments = Self.sortedLabelSegments(retainedLabelSegments + clampedUpdatedSegments)
        Task {
            try? await timelineLabelRepository.replaceLabelSegments(clampedUpdatedSegments, in: todayInterval)
        }
        refreshActivityViews()
    }

    private func refreshActivityViews() {
        let now = Date()
        let todayInterval = Self.dayInterval(containing: now)
        let insightInterval = Self.insightLoadInterval(containing: now)
        let insightIntervals = Self.mergedIntervals([insightInterval] + requestedInsightIntervals)
        let trackedSegments = Self.mergedTrackedSegments(persistedSegments + liveSegments)
        let trackedPeriods = Self.trackedSegmentsByPeriod(
            from: trackedSegments,
            todayInterval: todayInterval,
            insightIntervals: insightIntervals
        )
        let todaySegments = Self.sortedSegments(
            trackedPeriods.today + Self.manualSegments(from: manualEvents, in: todayInterval)
        )
        let pastInsightIntervals = insightIntervals.compactMap { interval -> DateInterval? in
            guard interval.start < now else { return nil }
            return DateInterval(start: interval.start, end: min(interval.end, now))
        }
        let combinedInsightSegments = Self.sortedSegments(
            trackedPeriods.insight + Self.manualSegments(from: manualEvents, in: pastInsightIntervals)
        )
        let todayDisplaySegments = todaySegments
        let insightDisplaySegments = combinedInsightSegments
        let todayLabelSegments = Self.labelSegments(overlapping: todayInterval, from: labelSegments)
        let insightLabelSegments = Self.labelSegments(overlapping: insightIntervals, from: labelSegments)
        let todayMetricSegments = metricSegments(from: todaySegments, applying: todayLabelSegments)
        let insightMetricSegments = metricSegments(from: combinedInsightSegments, applying: insightLabelSegments)
        let updatedOverview = overview(
            from: todayMetricSegments,
            displaying: todayDisplaySegments,
            on: now
        )

        self.todayMetricSegments = todayMetricSegments
        self.insightMetricSegments = insightMetricSegments
        insightSegments = insightDisplaySegments
        overview = updatedOverview
    }

    private func shouldRefreshLiveViews(for segments: [ActivitySegment], at date: Date) -> Bool {
        let dayStart = Self.dayInterval(containing: date).start
        defer {
            lastRefreshedLiveSegments = segments
            lastRefreshedLiveDayStart = dayStart
        }

        return segments != lastRefreshedLiveSegments || dayStart != lastRefreshedLiveDayStart
    }

    private func overview(
        from statsSegments: [ActivitySegment],
        displaying displaySegments: [ActivitySegment],
        on date: Date
    ) -> DailyActivityOverview {
        let statsOverview = insightEngine.dailyOverview(from: statsSegments, on: date)
        return DailyActivityOverview(
            date: statsOverview.date,
            productiveTime: statsOverview.productiveTime,
            unproductiveTime: statsOverview.unproductiveTime,
            unknownTime: statsOverview.unknownTime,
            totalTrackedTime: statsOverview.totalTrackedTime,
            segments: displaySegments
        )
    }

    private func metricSegments(
        from segments: [ActivitySegment],
        applying labelSegments: [TimelineLabelSegment]
    ) -> [ActivitySegment] {
        guard !labelSegments.isEmpty else { return segments }
        return Self.segments(segments, applying: labelSegments)
    }

    private func persistLiveSegments() async {
        let segmentsToPersist = liveSegments.filter { segment in
            guard !deletedSegmentIDs.contains(segment.id) else { return false }
            return lastPersistedLiveSegmentsByID[segment.id] != segment
        }
        guard !segmentsToPersist.isEmpty else { return }

        do {
            try await activityRepository.save(segmentsToPersist)
            for segment in segmentsToPersist {
                lastPersistedLiveSegmentsByID[segment.id] = segment
            }
            persistedSegments = Self.mergedTrackedSegments(persistedSegments + segmentsToPersist)
                .filter { !deletedSegmentIDs.contains($0.id) }
        } catch {
            // Live tracking should continue even if disk persistence temporarily fails.
        }
    }

    private static func sortedSegments(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }

            return $0.startDate < $1.startDate
        }
    }

    private static func trackedSegmentsByPeriod(
        from segments: [ActivitySegment],
        todayInterval: DateInterval,
        insightIntervals: [DateInterval]
    ) -> (today: [ActivitySegment], insight: [ActivitySegment]) {
        var todaySegments: [ActivitySegment] = []
        var insightSegments: [ActivitySegment] = []

        for segment in segments {
            guard let segmentInterval = segment.safeInterval else { continue }
            if strictlyIntersects(todayInterval, segmentInterval) {
                todaySegments.append(segment)
            }
            if insightIntervals.contains(where: { strictlyIntersects($0, segmentInterval) }) {
                insightSegments.append(segment)
            }
        }

        return (todaySegments, insightSegments)
    }



    private static func dayInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        if let interval = calendar.dateInterval(of: .day, for: date) {
            return interval
        }

        return DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
    }

    private static func clampedLabelSegments(_ segments: [TimelineLabelSegment], to interval: DateInterval) -> [TimelineLabelSegment] {
        sortedLabelSegments(segments.compactMap { segment in
            guard segment.endDate > segment.startDate else { return nil }
            let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
            guard strictlyIntersects(interval, segmentInterval) else { return nil }

            let startDate = max(segment.startDate, interval.start)
            let endDate = min(segment.endDate, interval.end)
            guard endDate > startDate else { return nil }
            return TimelineLabelSegment(
                id: segment.id,
                label: segment.label,
                startDate: startDate,
                endDate: endDate
            )
        })
    }

    private static func labelSegments(of segment: TimelineLabelSegment, outside interval: DateInterval) -> [TimelineLabelSegment] {
        guard segment.endDate > segment.startDate else { return [] }
        let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
        guard strictlyIntersects(interval, segmentInterval) else { return [segment] }

        var pieces: [TimelineLabelSegment] = []
        if interval.start > segment.startDate {
            pieces.append(TimelineLabelSegment(
                id: segment.id,
                label: segment.label,
                startDate: segment.startDate,
                endDate: min(interval.start, segment.endDate)
            ))
        }
        if interval.end < segment.endDate {
            // Use a new UUID for the trailing piece when both pieces are produced so that
            // a label segment straddling the replacement interval never results in two
            // TimelineLabelSegments carrying the same UUID — which would violate
            // Identifiable uniqueness and corrupt the in-memory label array.
            pieces.append(TimelineLabelSegment(
                id: pieces.isEmpty ? segment.id : UUID(),
                label: segment.label,
                startDate: max(interval.end, segment.startDate),
                endDate: segment.endDate
            ))
        }
        return pieces.filter { $0.endDate > $0.startDate }
    }

    private static func labelSegments(overlapping interval: DateInterval, from segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        clampedLabelSegments(segments, to: interval)
    }

    private static func labelSegments(overlapping intervals: [DateInterval], from segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        let clampedSegments = intervals.flatMap { interval in
            clampedLabelSegments(segments, to: interval)
        }
        return mergedLabelSegments(clampedSegments)
    }

    private static func sortedLabelSegments(_ segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        segments.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }

            return $0.startDate < $1.startDate
        }
    }

    private static func segments(_ segments: [ActivitySegment], applying labelSegments: [TimelineLabelSegment]) -> [ActivitySegment] {
        let sortedLabels = TimelineLabelSegment.normalized(labelSegments)

        guard !sortedLabels.isEmpty else { return segments }

        let sortedInputSegments = sortedSegments(segments)
        var labelStartIndex = 0

        return sortedSegments(sortedInputSegments.flatMap { segment -> [ActivitySegment] in
            guard !segment.isLifecycleContext,
                  !segment.isSleepEvent,
                  let segmentInterval = segment.safeInterval else {
                return [segment]
            }

            while labelStartIndex < sortedLabels.count,
                  sortedLabels[labelStartIndex].endDate <= segment.startDate {
                labelStartIndex += 1
            }

            var overlappingLabels: [TimelineLabelSegment] = []
            var scanIndex = labelStartIndex
            while scanIndex < sortedLabels.count,
                  sortedLabels[scanIndex].startDate < segment.endDate {
                let labelSegment = sortedLabels[scanIndex]
                if strictlyIntersects(segmentInterval, DateInterval(start: labelSegment.startDate, end: labelSegment.endDate)) {
                    overlappingLabels.append(labelSegment)
                }
                scanIndex += 1
            }

            guard !overlappingLabels.isEmpty else { return [segment] }
            return labeledPieces(of: segment, using: overlappingLabels)
        })
    }

    private static func labeledPieces(of segment: ActivitySegment, using labelSegments: [TimelineLabelSegment]) -> [ActivitySegment] {
        let boundaries = Set(
            [segment.startDate, segment.endDate]
            + labelSegments.flatMap { labelSegment in
                [
                    max(segment.startDate, labelSegment.startDate),
                    min(segment.endDate, labelSegment.endDate)
                ]
            }
        )
        .filter { $0 >= segment.startDate && $0 <= segment.endDate }
        .sorted()

        guard boundaries.count > 1 else { return [segment] }

        return boundaries.indices.dropLast().compactMap { index in
            let startDate = boundaries[index]
            let endDate = boundaries[index + 1]
            guard endDate > startDate else { return nil }

            let midpoint = startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)
            let overridingLabel = labelSegments.last { labelSegment in
                labelSegment.startDate <= midpoint && midpoint < labelSegment.endDate
            }

            return ActivitySegment(
                id: segment.id,
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                title: segment.title,
                userDescription: segment.userDescription,
                startDate: startDate,
                endDate: endDate,
                category: overridingLabel.map { $0.label.category } ?? segment.category,
                label: overridingLabel.map(\.label) ?? segment.label,
                productivityScore: overridingLabel.map { $0.label.productivityScore } ?? segment.productivityScore
            )
        }
    }

    private static func strictlyIntersects(_ lhs: DateInterval, _ rhs: DateInterval) -> Bool {
        lhs.start < rhs.end && rhs.start < lhs.end
    }

    private static func mergedTrackedSegments(_ segments: [ActivitySegment]) -> [ActivitySegment] {
        var segmentsByID: [UUID: ActivitySegment] = [:]
        for segment in segments where segment.duration > 0 && !segment.isAppLifecycleAvailabilityContext {
            if let existing = segmentsByID[segment.id] {
                segmentsByID[segment.id] = segment.endDate >= existing.endDate ? segment : existing
            } else {
                segmentsByID[segment.id] = segment
            }
        }

        return sortedSegments(Array(segmentsByID.values))
    }

    private static func mergedLabelSegments(_ segments: [TimelineLabelSegment]) -> [TimelineLabelSegment] {
        var uniqueSegments: [String: TimelineLabelSegment] = [:]
        for segment in segments where segment.duration > 0 {
            let key = [
                segment.id.uuidString,
                segment.label.id,
                String(segment.startDate.timeIntervalSinceReferenceDate),
                String(segment.endDate.timeIntervalSinceReferenceDate)
            ].joined(separator: "|")
            uniqueSegments[key] = segment
        }

        return sortedLabelSegments(Array(uniqueSegments.values))
    }

    private static func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sortedIntervals = intervals
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        guard let firstInterval = sortedIntervals.first else { return [] }

        var mergedIntervals = [firstInterval]
        for interval in sortedIntervals.dropFirst() {
            guard let lastInterval = mergedIntervals.last else { continue }
            if interval.start <= lastInterval.end {
                mergedIntervals.removeLast()
                mergedIntervals.append(DateInterval(start: lastInterval.start, end: max(lastInterval.end, interval.end)))
            } else {
                mergedIntervals.append(interval)
            }
        }

        return mergedIntervals
    }

    private static func loadSegments(
        from repository: any ActivityRepository,
        in intervals: [DateInterval]
    ) async throws -> [ActivitySegment] {
        var loadedSegments: [ActivitySegment] = []
        for interval in mergedIntervals(intervals) {
            loadedSegments.append(contentsOf: try await repository.segments(for: interval))
        }
        return mergedTrackedSegments(loadedSegments)
    }

    private static func loadLabelSegments(
        from repository: any TimelineLabelRepository,
        in intervals: [DateInterval]
    ) async throws -> [TimelineLabelSegment] {
        var loadedSegments: [TimelineLabelSegment] = []
        for interval in mergedIntervals(intervals) {
            loadedSegments.append(contentsOf: try await repository.labelSegments(for: interval))
        }
        return mergedLabelSegments(loadedSegments)
    }

    private static func manualSegments(from events: [ManualActivityEvent], in interval: DateInterval) -> [ActivitySegment] {
        manualSegments(from: events, in: [interval])
    }

    private static func manualSegments(from events: [ManualActivityEvent], in intervals: [DateInterval]) -> [ActivitySegment] {
        sortedSegments(intervals.flatMap { interval in
            events.flatMap { $0.segments(in: interval) }
        })
    }

    private func manualEventIDs(matching segment: ActivitySegment) -> Set<UUID> {
        if manualEvents.contains(where: { $0.id == segment.id }) {
            return [segment.id]
        }
        guard segment.isManualEventContext, let segmentInterval = segment.safeInterval else { return [] }

        return Set(manualEvents.compactMap { event in
            event.segments(in: segmentInterval).contains { $0.id == segment.id } ? event.id : nil
        })
    }

    private static func sortedManualEvents(_ events: [ManualActivityEvent]) -> [ManualActivityEvent] {
        events.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }

            return $0.startDate < $1.startDate
        }
    }

    private static func normalizedManualEventForToday(_ event: ManualActivityEvent, calendar: Calendar = .current) -> ManualActivityEvent {
        let todayInterval = dayInterval(containing: Date(), calendar: calendar)
        let startDate = max(todayInterval.start, min(event.startDate, todayInterval.end.addingTimeInterval(-60)))
        let endDate = event.endDate > event.startDate
            ? max(startDate.addingTimeInterval(60), min(event.endDate, todayInterval.end))
            : event.endDate

        guard event.recurrence == .none && event.endDate > event.startDate else {
            return ManualActivityEvent(
                id: event.id,
                title: event.title,
                startDate: event.startDate,
                endDate: event.endDate,
                label: event.label,
                isSleep: event.isSleep,
                recurrence: event.recurrence,
                alert: event.alert,
                weekdayMask: event.weekdayMask
            )
        }

        return ManualActivityEvent(
            id: event.id,
            title: event.title,
            startDate: startDate,
            endDate: endDate,
            label: event.label,
            isSleep: event.isSleep,
            recurrence: event.recurrence,
            alert: event.alert,
            weekdayMask: event.weekdayMask
        )
    }

    private static func insightLoadInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        let yearInterval = yearInterval(containing: date, calendar: calendar)
        let analyticsLookbackStart = calendar.date(
            byAdding: .day,
            value: -89,
            to: calendar.startOfDay(for: date)
        ) ?? yearInterval.start

        return DateInterval(
            start: min(yearInterval.start, analyticsLookbackStart),
            end: max(yearInterval.end, date)
        )
    }

    private static func yearInterval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        if let interval = calendar.dateInterval(of: .year, for: date) {
            return interval
        }

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }
}
