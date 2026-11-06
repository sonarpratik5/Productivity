import Testing
@testable import Productivity
import AppKit
import Foundation

// MARK: - Shared helpers (mirrors TimelineAlgorithmTests.swift helpers)

private let edge_epoch = Date(timeIntervalSinceReferenceDate: 0)

private func edate(_ seconds: TimeInterval) -> Date {
    edge_epoch.addingTimeInterval(seconds)
}

private func esegment(
    start: TimeInterval,
    end: TimeInterval,
    score: Double = 0.5,
    category: ActivityCategory = .focus,
    appName: String = "TestApp",
    bundleID: String = "com.test.app",
    companion: Bool = false,
    lifecycle: Bool = false,
    manual: Bool = false,
    sleep: Bool = false
) -> ActivitySegment {
    let resolvedBundleID: String
    if sleep {
        resolvedBundleID = "manual.event.sleep.bedtime"
    } else if manual {
        resolvedBundleID = "manual.event.focus"
    } else if lifecycle {
        resolvedBundleID = "productivity.lifecycle.opened"
    } else {
        resolvedBundleID = bundleID
    }

    return ActivitySegment(
        appName: appName,
        bundleIdentifier: resolvedBundleID,
        title: appName,
        userDescription: companion ? "Background companion activity" : nil,
        startDate: edate(start),
        endDate: edate(end),
        category: category,
        productivityScore: score
    )
}

private func elabel(
    start: TimeInterval,
    end: TimeInterval,
    label: ActivityLabel = .productive
) -> TimelineLabelSegment {
    TimelineLabelSegment(label: label, startDate: edate(start), endDate: edate(end))
}

// MARK: - DurationFormatting.abbreviated

@Suite("DurationFormatting.abbreviated")
struct DurationFormattingTests {

    @Test("zero seconds → 0m")
    func zeroSeconds() {
        #expect(DurationFormatting.abbreviated(0) == "0m")
    }

    @Test("negative interval clamps to 0m")
    func negativeInterval() {
        #expect(DurationFormatting.abbreviated(-120) == "0m")
    }

    @Test("59 seconds (sub-minute) → 0m")
    func subMinute() {
        #expect(DurationFormatting.abbreviated(59) == "0m")
    }

    @Test("exactly 60 seconds → 1m")
    func exactlyOneMinute() {
        #expect(DurationFormatting.abbreviated(60) == "1m")
    }

    @Test("90 seconds → 1m (truncated, not rounded)")
    func ninetySeconds() {
        #expect(DurationFormatting.abbreviated(90) == "1m")
    }

    @Test("exactly 1 hour → 1h 0m")
    func exactlyOneHour() {
        #expect(DurationFormatting.abbreviated(3600) == "1h 0m")
    }

    @Test("1 hour 30 minutes → 1h 30m")
    func oneHourThirtyMinutes() {
        #expect(DurationFormatting.abbreviated(5400) == "1h 30m")
    }

    @Test("23 hours 59 minutes → 23h 59m")
    func almostOneDay() {
        #expect(DurationFormatting.abbreviated(23 * 3600 + 59 * 60) == "23h 59m")
    }
}

// MARK: - PullTimerDurationCalculator

@Suite("Pull timer gesture")
struct PullTimerGestureTests {
    @Test("a pull below the activation threshold does not start a timer")
    func belowThresholdDoesNotCreateDuration() {
        let distance = PullTimerDurationCalculator.minimumDragThreshold - 1
        #expect(PullTimerDurationCalculator.calculateDuration(dragDistanceY: distance) == 0)
    }

    @Test("a downward menu-bar pull maps to the expected focus duration")
    func downwardPullMapsToDuration() {
        let distance = PullTimerDurationCalculator.minimumDragThreshold + 160
        #expect(PullTimerDurationCalculator.calculateDuration(dragDistanceY: distance) == 25)
    }
}

// MARK: - DailyActivityOverview.productivityRatio

@Suite("DailyActivityOverview.productivityRatio")
struct ProductivityRatioTests {

    @Test("zero totalTrackedTime → ratio is 0.0 (no divide-by-zero)")
    func zeroTrackedTimeNoCrash() {
        let overview = DailyActivityOverview(
            date: Date(),
            productiveTime: 0,
            unproductiveTime: 0,
            unknownTime: 0,
            totalTrackedTime: 0,
            segments: []
        )
        #expect(overview.productivityRatio == 0.0)
    }

    @Test("100% productive → ratio is 1.0")
    func fullyProductive() {
        let overview = DailyActivityOverview(
            date: Date(),
            productiveTime: 3600,
            unproductiveTime: 0,
            unknownTime: 0,
            totalTrackedTime: 3600,
            segments: []
        )
        #expect(overview.productivityRatio == 1.0)
    }

    @Test("50% productive → ratio is 0.5")
    func halfProductive() {
        let overview = DailyActivityOverview(
            date: Date(),
            productiveTime: 1800,
            unproductiveTime: 1800,
            unknownTime: 0,
            totalTrackedTime: 3600,
            segments: []
        )
        #expect(abs(overview.productivityRatio - 0.5) < 0.0001)
    }

    @Test("0 productive out of non-zero tracked → ratio is 0")
    func noneProductive() {
        let overview = DailyActivityOverview(
            date: Date(),
            productiveTime: 0,
            unproductiveTime: 3600,
            unknownTime: 0,
            totalTrackedTime: 3600,
            segments: []
        )
        #expect(overview.productivityRatio == 0.0)
    }
}

// MARK: - InsightEngine.summaries

@Suite("InsightEngine.summaries")
struct InsightEngineSummaryTests {

    private func overview(
        productive: TimeInterval = 0,
        unproductive: TimeInterval = 0,
        unknown: TimeInterval = 0
    ) -> DailyActivityOverview {
        DailyActivityOverview(
            date: Date(),
            productiveTime: productive,
            unproductiveTime: unproductive,
            unknownTime: unknown,
            totalTrackedTime: productive + unproductive + unknown,
            segments: []
        )
    }

    @Test("always returns exactly 3 summaries")
    func returnsThreeSummaries() {
        let summaries = InsightEngine().summaries(from: overview(productive: 1800, unproductive: 900, unknown: 300))
        #expect(summaries.count == 3)
    }

    @Test("productive summary has correct formatted duration")
    func productiveDuration() {
        let summaries = InsightEngine().summaries(from: overview(productive: 3600))
        let productive = summaries.first { $0.title == "Productive" }
        #expect(productive?.value == "1h 0m")
    }

    @Test("productive summary trend shows correct integer percentage")
    func productivityPercentage() {
        // 1800 productive / 3600 total = 50%
        let summaries = InsightEngine().summaries(from: overview(productive: 1800, unproductive: 1800))
        let productive = summaries.first { $0.title == "Productive" }
        #expect(productive?.trend == "50% of tracked time")
    }

    @Test("zero tracked time: productive trend shows 0%")
    func zeroTrackedTimePercent() {
        let summaries = InsightEngine().summaries(from: overview())
        let productive = summaries.first { $0.title == "Productive" }
        #expect(productive?.trend == "0% of tracked time")
    }

    @Test("summary categories are focus, entertainment, unknown in order")
    func summaryCategories() {
        let summaries = InsightEngine().summaries(from: overview(productive: 1800))
        #expect(summaries[0].category == .focus)
        #expect(summaries[1].category == .entertainment)
        #expect(summaries[2].category == .unknown)
    }
}

// MARK: - ActivityLabel.from(category:)

@Suite("ActivityLabel.from(category:)")
struct ActivityLabelFromCategoryTests {

    @Test("focus → focus")
    func focusIsFocus() {
        #expect(ActivityLabel.from(category: .focus) == .focus)
        #expect(ActivityLabel.from(category: .focus).commonRollup == .productive)
    }

    @Test("communication → productive")
    func communicationIsProductive() {
        #expect(ActivityLabel.from(category: .communication) == .productive)
    }

    @Test("research → productive")
    func researchIsProductive() {
        #expect(ActivityLabel.from(category: .research) == .productive)
    }

    @Test("entertainment → unproductive")
    func entertainmentIsUnproductive() {
        #expect(ActivityLabel.from(category: .entertainment) == .unproductive)
    }

    @Test("system → unproductive")
    func systemIsUnproductive() {
        #expect(ActivityLabel.from(category: .system) == .unproductive)
    }

    @Test("unknown → unknown")
    func unknownIsUnknown() {
        #expect(ActivityLabel.from(category: .unknown) == .unknown)
    }

    @Test("rollup duration includes specific productive labels")
    func rollupDurationIncludesSpecificProductiveLabels() {
        let items: [(label: ActivityLabel, duration: TimeInterval)] = [
            (.focus, 1_800),
            (.health, 900),
            (.productive, 300),
            (.unproductive, 600)
        ]

        #expect(ActivityLabel.rollupDuration(for: .productive, in: items) == 3_000)
        #expect(ActivityLabel.rollupDuration(for: .unproductive, in: items) == 600)
    }

    @Test("rollup duration ignores invalid durations")
    func rollupDurationIgnoresInvalidDurations() {
        let items: [(label: ActivityLabel, duration: TimeInterval)] = [
            (.focus, 600),
            (.productive, -120),
            (.productive, .infinity),
            (.unknown, 300)
        ]

        #expect(ActivityLabel.rollupDuration(for: .productive, in: items) == 600)
        #expect(ActivityLabel.rollupDuration(for: .unknown, in: items) == 300)
    }

    @Test("custom label definitions are saved and loaded")
    func customLabelDefinitionsAreSavedAndLoaded() {
        let suiteName = "ProductivityTests.customLabelDefinitionsAreSavedAndLoaded"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let definition = ActivityLabelDefinition(
            id: "custom.test.saved-label",
            title: "Deep Work",
            systemImage: "scope",
            symbol: nil,
            tint: ActivityLabelColor(red: 0.2, green: 0.7, blue: 0.6),
            rollup: .productive
        )

        ActivityLabelCatalog.saveCustomDefinitions([definition], defaults: defaults)

        #expect(ActivityLabelCatalog.customDefinitions(defaults: defaults) == [definition])
    }
}

// MARK: - ActivitySegment context predicates

@Suite("ActivitySegment context predicates")
struct ActivitySegmentPredicateTests {

    @Test("manual.event.sleep.* bundleID → isSleepEvent")
    func sleepManualEventBundleID() {
        let seg = esegment(start: 0, end: 60, sleep: true)
        #expect(seg.isSleepEvent)
        #expect(seg.isManualSleepEvent)
        #expect(seg.isDayProgressEvent)
        #expect(!seg.isDayProgressDisplayEvent)
    }

    @Test("productivity.lifecycle.sleep bundleID → isSleepEvent")
    func lifecycleSleepBundleID() {
        let seg = ActivitySegment(
            appName: "Sleep",
            bundleIdentifier: "productivity.lifecycle.sleep",
            title: "Sleep",
            startDate: edate(0),
            endDate: edate(60),
            category: .unknown,
            productivityScore: 0
        )
        #expect(seg.isSleepEvent)
    }

    @Test("productivity.lifecycle.sleep is not a day progress boundary")
    func lifecycleSleepIsNotDayProgressBoundary() {
        let seg = ActivitySegment(
            appName: "Sleep",
            bundleIdentifier: "productivity.lifecycle.sleep",
            title: "Sleep",
            startDate: edate(0),
            endDate: edate(60 * 60),
            category: .unknown,
            productivityScore: 0
        )

        #expect(seg.isSleepEvent)
        #expect(!seg.isManualSleepEvent)
        #expect(!seg.isDayProgressEvent)
        #expect(!seg.isDayProgressDisplayEvent)
        #expect(!seg.isDayProgressSleepBoundary)
    }

    @Test("standard bundleID → not isSleepEvent")
    func standardAppNotSleep() {
        let seg = esegment(start: 0, end: 60)
        #expect(!seg.isSleepEvent)
    }

    @Test("manual.event.* bundleID → isManualEventContext")
    func manualEventPrefix() {
        let seg = esegment(start: 0, end: 60, manual: true)
        #expect(seg.isManualEventContext)
        #expect(seg.isDayProgressEvent)
        #expect(seg.isDayProgressDisplayEvent)
    }

    @Test("standard bundleID → not isManualEventContext")
    func standardNotManualContext() {
        let seg = esegment(start: 0, end: 60, bundleID: "com.apple.xcode")
        #expect(!seg.isManualEventContext)
    }

    @Test("productivity.lifecycle.* bundleID → isLifecycleContext")
    func lifecyclePrefix() {
        let seg = esegment(start: 0, end: 60, lifecycle: true)
        #expect(seg.isLifecycleContext)
    }

    @Test("companion userDescription → isCompanionContext")
    func companionUserDescription() {
        let seg = esegment(start: 0, end: 60, companion: true)
        #expect(seg.isCompanionContext)
    }

    @Test("nil userDescription → not isCompanionContext")
    func nilDescriptionNotCompanion() {
        let seg = esegment(start: 0, end: 60)
        #expect(!seg.isCompanionContext)
    }

    @Test("negative-duration segment has no safeInterval")
    func negativeDurationNoSafeInterval() {
        let seg = esegment(start: 60, end: 0)
        #expect(seg.safeInterval == nil)
    }

    @Test("zero-duration segment has no safeInterval")
    func zeroDurationNoSafeInterval() {
        let seg = esegment(start: 30, end: 30)
        #expect(seg.safeInterval == nil)
    }

    @Test("short sleep event is not a day progress sleep boundary")
    func shortSleepEventIsNotDayProgressBoundary() {
        let seg = esegment(start: 0, end: 9 * 60, sleep: true)
        #expect(seg.isSleepEvent)
        #expect(!seg.isDayProgressSleepBoundary)
    }

    @Test("ten minute sleep event is a day progress sleep boundary")
    func tenMinuteSleepEventIsDayProgressBoundary() {
        let seg = esegment(start: 0, end: 10 * 60, sleep: true)
        #expect(seg.isDayProgressSleepBoundary)
    }

    @Test("non-sleep event is never a day progress sleep boundary")
    func nonSleepEventIsNotDayProgressBoundary() {
        let seg = esegment(start: 0, end: 60 * 60)
        #expect(!seg.isDayProgressSleepBoundary)
    }
}

// MARK: - ManualActivityEvent sleep flow

@Suite("ManualActivityEvent sleep flow")
struct ManualActivityEventSleepFlowTests {

    @Test("sleep event emits sleep segment")
    func sleepEventEmitsSleepSegment() {
        let event = ManualActivityEvent(
            title: "Sleep",
            startDate: edate(22 * 60 * 60),
            endDate: edate(23 * 60 * 60),
            label: .productive,
            isSleep: true,
            recurrence: .none
        )

        let segments = event.segments(in: DateInterval(start: edate(0), end: edate(24 * 60 * 60)))
        #expect(segments.count == 1)
        #expect(segments[0].isSleepEvent)
        #expect(segments[0].isDayProgressSleepBoundary)
    }

    @Test("cross-midnight sleep event contributes to next day progress")
    func crossMidnightSleepContributesToNextDayProgress() {
        let event = ManualActivityEvent(
            title: "Sleep",
            startDate: edate(23 * 60 * 60),
            endDate: edate(6 * 60 * 60),
            label: .productive,
            isSleep: true,
            recurrence: .none
        )
        let nextDay = DateInterval(start: edate(24 * 60 * 60), end: edate(48 * 60 * 60))

        let segments = event.segments(in: nextDay)
        #expect(segments.count == 1)
        #expect(segments[0].startDate == nextDay.start)
        #expect(segments[0].endDate == edate(30 * 60 * 60))
        #expect(segments[0].isDayProgressSleepBoundary)
    }

    @Test("manual form normalization preserves overnight sleep")
    func manualFormNormalizationPreservesOvernightSleep() {
        let day = DateInterval(start: edate(0), end: edate(24 * 60 * 60))
        let event = normalizedManualActivityEventInput(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            title: "Sleep",
            startDate: edate(23 * 60 * 60),
            endDate: edate(7 * 60 * 60),
            label: .sleep,
            isSleep: true,
            recurrence: .daily,
            alert: .none,
            weekdayMask: [],
            dayInterval: day
        )

        #expect(event.endDate < event.startDate)

        let segments = event.segments(in: day)
        let allSegmentsAreSleep = segments.allSatisfy { $0.isSleepEvent }
        let allSegmentsHideFromDayProgress = segments.allSatisfy { $0.isDayProgressSleepBoundary }
        #expect(segments.count == 2)
        #expect(allSegmentsAreSleep)
        #expect(allSegmentsHideFromDayProgress)
    }

    @Test("sleep time picker allows user-entered overnight end")
    func sleepTimePickerAllowsUserEnteredOvernightEnd() {
        let day = DateInterval(start: edate(0), end: edate(24 * 60 * 60))
        let start = edate(23 * 60 * 60)
        let overnightEnd = edate(7 * 60 * 60)

        let endAfterStartChange = normalizedManualActivityEndDateAfterStartChange(
            startDate: start,
            endDate: overnightEnd,
            dayInterval: day,
            allowsOvernight: true
        )
        let endAfterEndChange = normalizedManualActivityEndDateAfterEndChange(
            startDate: start,
            endDate: overnightEnd,
            dayInterval: day,
            allowsOvernight: true
        )

        #expect(endAfterStartChange == overnightEnd)
        #expect(endAfterEndChange == overnightEnd)
    }

    @Test("non-sleep time picker keeps same-day minimum duration")
    func nonSleepTimePickerKeepsSameDayMinimumDuration() {
        let day = DateInterval(start: edate(0), end: edate(24 * 60 * 60))
        let start = edate(23 * 60 * 60)
        let earlierEnd = edate(7 * 60 * 60)

        let normalizedEnd = normalizedManualActivityEndDateAfterEndChange(
            startDate: start,
            endDate: earlierEnd,
            dayInterval: day,
            allowsOvernight: false
        )

        #expect(normalizedEnd == edate((23 * 60 * 60) + (30 * 60)))
    }
}

// MARK: - TimelineLabelSegment.normalized - additional edge cases

@Suite("TimelineLabelSegment.normalized - additional edge cases")
struct NormalizedLabelEdgeCaseTests {

    @Test("reverse-order input produces same result as sorted input")
    func reverseOrderSameResult() {
        let forward: [TimelineLabelSegment] = [
            elabel(start: 0,  end: 30, label: .productive),
            elabel(start: 30, end: 60, label: .unproductive),
            elabel(start: 60, end: 90, label: .unknown)
        ]
        let reversed: [TimelineLabelSegment] = forward.reversed()
        let resultForward  = TimelineLabelSegment.normalized(forward)
        let resultReversed = TimelineLabelSegment.normalized(reversed)
        #expect(resultForward.count == resultReversed.count)
        for (a, b) in zip(resultForward, resultReversed) {
            #expect(a.label == b.label)
            #expect(abs(a.duration - b.duration) < 0.001)
        }
    }

    @Test("many adjacent same-label segments collapse into one")
    func manyAdjacentCollapse() {
        let input = (0..<10).map { i in
            elabel(start: TimeInterval(i * 10), end: TimeInterval((i + 1) * 10), label: .productive)
        }
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 1)
        #expect(abs(result[0].duration - 100) < 0.001)
        #expect(result[0].label == .productive)
    }

    @Test("gap between same-label segments preserves two separate output segments")
    func gapBreaksMerge() {
        let input = [
            elabel(start: 0,  end: 30, label: .productive),
            elabel(start: 60, end: 90, label: .productive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 2)
        #expect(result[0].endDate == edate(30))
        #expect(result[1].startDate == edate(60))
    }

    @Test("single-millisecond segment is kept (duration > 0)")
    func singleMillisecondKept() {
        let input = [elabel(start: 0, end: 0.001, label: .productive)]
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 1)
        #expect(result[0].duration > 0)
    }

    @Test("fully overlapping same-label duplicates: total output duration equals span")
    func duplicateSameLabelCollapsed() {
        let input = [
            elabel(start: 0, end: 60, label: .productive),
            elabel(start: 0, end: 60, label: .productive),
            elabel(start: 0, end: 60, label: .productive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        let total = result.reduce(0) { $0 + $1.duration }
        #expect(total <= 60 + 0.001)
        #expect(result.allSatisfy { $0.label == .productive })
    }

    @Test("overlapping mixed labels: no overlap in output and total duration equals span")
    func overlappingMixedLabelsNoOverlap() {
        let input = [
            elabel(start: 0,  end: 90, label: .productive),
            elabel(start: 30, end: 60, label: .unproductive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        let total = result.reduce(0) { $0 + $1.duration }
        #expect(abs(total - 90) < 0.001)
        for i in result.indices.dropLast() {
            #expect(result[i].endDate <= result[i + 1].startDate)
        }
    }
}

// MARK: - ActivitySegment.primaryAttentionSegments - additional edge cases

@Suite("ActivitySegment.primaryAttentionSegments - additional edge cases")
struct PrimaryAttentionEdgeCaseTests {

    @Test("reverse-order input produces same total duration as sorted input")
    func reverseOrderSameTotalDuration() {
        let forward = [
            esegment(start: 0,  end: 30, appName: "A"),
            esegment(start: 30, end: 60, appName: "B"),
            esegment(start: 60, end: 90, appName: "C")
        ]
        let reversed: [ActivitySegment] = forward.reversed()
        let totalForward  = ActivitySegment.primaryAttentionSegments(from: forward).reduce(0)  { $0 + $1.duration }
        let totalReversed = ActivitySegment.primaryAttentionSegments(from: reversed).reduce(0) { $0 + $1.duration }
        #expect(abs(totalForward - totalReversed) < 0.001)
    }

    @Test("zero-duration segments are silently filtered out")
    func zeroDurationFiltered() {
        let input = [
            esegment(start: 30, end: 30),             // zero-duration: filtered
            esegment(start: 0,  end: 60, appName: "Valid")
        ]
        let result = ActivitySegment.primaryAttentionSegments(from: input)
        #expect(result.allSatisfy { $0.duration > 0 })
        #expect(result.allSatisfy { $0.appName == "Valid" })
    }

    @Test("lifecycle + companion + primary in same input: only primary appears in output")
    func mixedContextsOnlyPrimary() {
        let primary   = esegment(start: 0, end: 60, appName: "Xcode")
        let companion = esegment(start: 0, end: 60, appName: "Spotify", companion: true)
        let lifecycle = esegment(start: 0, end: 60, lifecycle: true)
        let result = ActivitySegment.primaryAttentionSegments(from: [primary, companion, lifecycle])
        #expect(result.allSatisfy { $0.appName == "Xcode" })
        #expect(abs(result.reduce(0) { $0 + $1.duration } - 60) < 0.001)
    }

    @Test("equal-score overlap: earlier-started segment retains attention until it ends")
    func equalScoreEarlierStartRetainsAttention() {
        // A [0-60] score 0.5, B [30-90] score 0.5
        // A arrived first and retains attention for [0-60]; B only wins [60-90]
        let a = esegment(start: 0,  end: 60, score: 0.5, appName: "A", bundleID: "com.a")
        let b = esegment(start: 30, end: 90, score: 0.5, appName: "B", bundleID: "com.b")
        let result = ActivitySegment.primaryAttentionSegments(from: [a, b])
        let aDuration = result.filter { $0.appName == "A" }.reduce(0) { $0 + $1.duration }
        let bDuration = result.filter { $0.appName == "B" }.reduce(0) { $0 + $1.duration }
        #expect(abs(aDuration - 60) < 0.001)
        #expect(abs(bDuration - 30) < 0.001)
    }

    @Test("all excluded contexts (companion + lifecycle): output is empty")
    func allExcludedContextsEmpty() {
        let result = ActivitySegment.primaryAttentionSegments(from: [
            esegment(start: 0, end: 60, companion: true),
            esegment(start: 0, end: 60, lifecycle: true)
        ])
        #expect(result.isEmpty)
    }
}

// MARK: - TimelineStream.packed - companion same-bundleID overlap removal

@Suite("TimelineStream.packed - companion overlap removal")
struct CompanionOverlapRemovalTests {

    @Test("companion fully covered by same-bundleID primary: companion lane is absent")
    func sameBundleIDFullyCoveredCompanionRemoved() {
        let primary   = esegment(start: 0, end: 60, appName: "Safari", bundleID: "com.apple.safari")
        let companion = esegment(start: 0, end: 60, appName: "Safari", bundleID: "com.apple.safari", companion: true)
        let streams = TimelineStream.packed(from: [primary, companion])
        #expect(streams.count == 1)
    }

    @Test("companion partially overlaps same-bundleID primary: non-overlapping remainder kept")
    func sameBundleIDPartialOverlapRemainder() {
        // Primary: Safari 0-30 | Companion: Safari 0-60 → remainder: Safari 30-60
        let primary   = esegment(start: 0, end: 30, appName: "Safari", bundleID: "com.apple.safari")
        let companion = esegment(start: 0, end: 60, appName: "Safari", bundleID: "com.apple.safari", companion: true)
        let streams = TimelineStream.packed(from: [primary, companion])
        #expect(streams.count == 2)
        let companionTotal = streams.first { $0.number == 2 }?.segments.reduce(0) { $0 + $1.duration } ?? 0
        #expect(abs(companionTotal - 30) < 0.001)
    }

    @Test("companion with different bundleID from primary: not subtracted, full duration kept")
    func differentBundleIDNotSubtracted() {
        let primary   = esegment(start: 0, end: 60, appName: "Xcode",   bundleID: "com.apple.dt.Xcode")
        let companion = esegment(start: 0, end: 60, appName: "Spotify", bundleID: "com.spotify.client", companion: true)
        let streams = TimelineStream.packed(from: [primary, companion])
        #expect(streams.count == 2)
        let companionTotal = streams.first { $0.number == 2 }?.segments.reduce(0) { $0 + $1.duration } ?? 0
        #expect(abs(companionTotal - 60) < 0.001)
    }

    @Test("only lifecycle segments: one stream is produced")
    func onlyLifecycleProducesOneStream() {
        let streams = TimelineStream.packed(from: [esegment(start: 0, end: 60, lifecycle: true)])
        #expect(streams.count == 1)
    }
}

// MARK: - MacOSActivityTracker foreground eligibility

@Suite("MacOSActivityTracker foreground eligibility")
struct ForegroundTrackingEligibilityTests {

    @Test("regular Dock applications are eligible for primary tracking")
    func regularApplicationIsEligible() {
        let isEligible = MacOSActivityTracker.isForegroundTrackableActivationPolicy(
            .regular,
            bundleIdentifier: "com.example.editor",
            ignoredBundleIdentifier: "com.example.productivity"
        )

        #expect(isEligible)
    }

    @Test("accessory and prohibited applications are ignored as primary foreground apps")
    func nonDockApplicationsAreIgnored() {
        let accessoryIsEligible = MacOSActivityTracker.isForegroundTrackableActivationPolicy(
            .accessory,
            bundleIdentifier: "com.example.menu-agent",
            ignoredBundleIdentifier: "com.example.productivity"
        )
        let prohibitedIsEligible = MacOSActivityTracker.isForegroundTrackableActivationPolicy(
            .prohibited,
            bundleIdentifier: "com.example.background-agent",
            ignoredBundleIdentifier: "com.example.productivity"
        )

        #expect(!accessoryIsEligible)
        #expect(!prohibitedIsEligible)
    }

    @Test("the Productivity app remains eligible when reviewing its own dashboard")
    func ownApplicationRemainsEligible() {
        let isEligible = MacOSActivityTracker.isForegroundTrackableActivationPolicy(
            .accessory,
            bundleIdentifier: "com.example.productivity",
            ignoredBundleIdentifier: "com.example.productivity"
        )

        #expect(isEligible)
    }
}

// MARK: - TimelineLabelSegment.derived - additional edge cases

@Suite("TimelineLabelSegment.derived - additional edge cases")
struct DerivedLabelEdgeCaseTests {

    @Test("communication category → productive label")
    func communicationYieldsProductiveLabel() {
        let result = TimelineLabelSegment.derived(from: [
            esegment(start: 0, end: 60, score: 0.6, category: .communication)
        ])
        #expect(result.allSatisfy { $0.label == .productive })
    }

    @Test("research category → productive label")
    func researchYieldsProductiveLabel() {
        let result = TimelineLabelSegment.derived(from: [
            esegment(start: 0, end: 60, score: 0.7, category: .research)
        ])
        #expect(result.allSatisfy { $0.label == .productive })
    }

    @Test("system category → unproductive label")
    func systemYieldsUnproductiveLabel() {
        let result = TimelineLabelSegment.derived(from: [
            esegment(start: 0, end: 60, score: 0.1, category: .system)
        ])
        #expect(result.allSatisfy { $0.label == .unproductive })
    }

    @Test("unknown category → unknown label")
    func unknownCategoryYieldsUnknownLabel() {
        let result = TimelineLabelSegment.derived(from: [
            esegment(start: 0, end: 60, score: 0.0, category: .unknown)
        ])
        #expect(result.allSatisfy { $0.label == .unknown })
    }

    @Test("gap between two primary segments is filled with an unknown label")
    func gapBetweenSegmentsFilledWithUnknown() {
        // Xcode 0-30, gap 30-60, Xcode 60-90
        // derived() sweeps through all event times; when no segment is active it
        // emits .unknown — so the gap gets an unknown label, not silence.
        let input = [
            esegment(start: 0,  end: 30, appName: "Xcode"),
            esegment(start: 60, end: 90, appName: "Xcode")
        ]
        let result = TimelineLabelSegment.derived(from: input)
        // Total coverage spans the full 0-90 window (gap filled with .unknown)
        let totalCovered = result.reduce(0) { $0 + $1.duration }
        #expect(abs(totalCovered - 90) < 0.001)
        // The gap segment (30-60) must be .unknown
        let gapSegment = result.first { $0.startDate == edate(30) && $0.endDate == edate(60) }
        #expect(gapSegment?.label == .unknown)
    }

    @Test("adjacent derived segments with same label are merged into one")
    func adjacentDerivedSameLabelMerged() {
        let input = [
            esegment(start: 0,  end: 30, category: .focus),
            esegment(start: 30, end: 60, category: .focus)
        ]
        let result = TimelineLabelSegment.derived(from: input)
        #expect(result.count == 1)
        #expect(result[0].label == .focus)
        #expect(abs(result[0].duration - 60) < 0.001)
    }

    @Test("adjacent different-category segments produce two separate derived labels")
    func adjacentDifferentCategorySeparateLabels() {
        let input = [
            esegment(start: 0,  end: 30, category: .focus),
            esegment(start: 30, end: 60, category: .entertainment)
        ]
        let result = TimelineLabelSegment.derived(from: input)
        #expect(result.count == 2)
        #expect(result[0].label == .focus)
        #expect(result[1].label == .unproductive)
    }
}

// MARK: - Pomodoro timer controls and menu bar presentation

@Suite("Pomodoro timer controls and menu bar presentation")
struct PomodoroTimerControlsTests {

    @Test("preset durations include standard productivity focus intervals")
    @MainActor
    func presetDurationsMatchExpectedIntervals() {
        #expect(PomodoroViewModel.presetFocusDurations == [10, 15, 25, 45, 60])
    }

    @Test("setting focus duration switches phase to focus and resets remaining time")
    @MainActor
    func settingFocusDurationUpdatesPhaseAndRemainingTime() {
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        viewModel.setFocusDuration(15, resetTimer: true, startImmediately: false)

        #expect(viewModel.phase == .focus)
        #expect(viewModel.configuration.focusMinutes == 15)
        #expect(viewModel.remainingSeconds == 15 * 60)
        #expect(viewModel.totalSeconds == 15 * 60)
        #expect(viewModel.isRunning == false)
    }

    @Test("setting focus duration clamps out of bounds values")
    @MainActor
    func settingFocusDurationClampsOutOfBounds() {
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        viewModel.setFocusDuration(0, resetTimer: true)
        #expect(viewModel.configuration.focusMinutes == PomodoroConfiguration.focusMinutesRange.lowerBound)

        viewModel.setFocusDuration(250, resetTimer: true)
        #expect(viewModel.configuration.focusMinutes == PomodoroConfiguration.focusMinutesRange.upperBound)
    }

    @Test("setting short and long break durations correctly updates phase and remaining time")
    @MainActor
    func settingBreakDurationsUpdatesState() {
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        viewModel.setShortBreakDuration(10, resetTimer: true, startImmediately: false)
        #expect(viewModel.phase == .shortBreak)
        #expect(viewModel.configuration.shortBreakMinutes == 10)
        #expect(viewModel.remainingSeconds == 10 * 60)

        viewModel.setLongBreakDuration(20, resetTimer: true, startImmediately: false)
        #expect(viewModel.phase == .longBreak)
        #expect(viewModel.configuration.longBreakMinutes == 20)
        #expect(viewModel.remainingSeconds == 20 * 60)
    }

    @Test("isTimerActive is true while running or partially elapsed")
    @MainActor
    func isTimerActiveReflectsRunningAndPartialStates() {
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        #expect(viewModel.isTimerActive == false)

        viewModel.toggleRunning()
        #expect(viewModel.isRunning == true)
        #expect(viewModel.isTimerActive == true)

        viewModel.adjustRemainingTime(by: -1)
        viewModel.toggleRunning() // pause
        #expect(viewModel.isRunning == false)
        #expect(viewModel.isTimerActive == true)

        viewModel.reset()
        #expect(viewModel.isRunning == false)
        #expect(viewModel.isTimerActive == false)
    }

    @Test("adjustRemainingTime clamps between 10 seconds and max duration")
    @MainActor
    func adjustRemainingTimeClamping() {
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        viewModel.adjustRemainingTime(by: 5)
        #expect(viewModel.remainingSeconds == 30 * 60)

        viewModel.adjustRemainingTime(by: -100)
        #expect(viewModel.remainingSeconds == 10)
    }
}

// MARK: - PullTimerDurationCalculator calculation and formatting

@Suite("PullTimerDurationCalculator calculation and formatting")
struct PullTimerDurationCalculatorTests {

    @Test("drag below minimum threshold returns 0 minutes")
    func belowThresholdReturnsZero() {
        #expect(PullTimerDurationCalculator.calculateDuration(dragDistanceY: 0) == 0)
        #expect(PullTimerDurationCalculator.calculateDuration(dragDistanceY: 5) == 0)
        #expect(PullTimerDurationCalculator.calculateDuration(dragDistanceY: 11.9) == 0)
    }

    @Test("short drag maps to natural 1-5 minutes")
    func shortDragNaturalMinutes() {
        let m1 = PullTimerDurationCalculator.calculateDuration(dragDistanceY: 15)
        #expect(m1 >= 1 && m1 <= 2)

        let m5 = PullTimerDurationCalculator.calculateDuration(dragDistanceY: 55)
        #expect(m5 >= 4 && m5 <= 6)
    }

    @Test("medium drag maps to 10-45 minutes range")
    func mediumDragMapsCorrectly() {
        let m25 = PullTimerDurationCalculator.calculateDuration(dragDistanceY: 175)
        #expect(m25 >= 20 && m25 <= 35)
    }

    @Test("long drag scales smoothly up to 180 minutes")
    func longDragScalesTo180() {
        let maxMinutes = PullTimerDurationCalculator.calculateDuration(dragDistanceY: 600)
        #expect(maxMinutes == 180)
    }

    @Test("formattedDuration produces clean human-readable text")
    func formattedDurationStrings() {
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 0) == "Pull down to set timer")
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 1) == "1 minute")
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 25) == "25 minutes")
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 60) == "1 hour")
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 90) == "1 hr 30 min")
        #expect(PullTimerDurationCalculator.formattedDuration(minutes: 120) == "2 hours")
    }

    @Test("shortFormattedDuration produces compact labels")
    func shortFormattedDurationLabels() {
        #expect(PullTimerDurationCalculator.shortFormattedDuration(minutes: 0) == "0m")
        #expect(PullTimerDurationCalculator.shortFormattedDuration(minutes: 15) == "15m")
        #expect(PullTimerDurationCalculator.shortFormattedDuration(minutes: 60) == "1h")
        #expect(PullTimerDurationCalculator.shortFormattedDuration(minutes: 75) == "1h 15m")
    }

    @Test("targetTimeString calculates future date accurately")
    func targetTimeStringAccurate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let refDate = Date(timeIntervalSince1970: 1700000000) // Known timestamp

        let str = PullTimerDurationCalculator.targetTimeString(minutes: 30, from: refDate, calendar: calendar)
        #expect(str.hasPrefix("Until "))
        #expect(PullTimerDurationCalculator.targetTimeString(minutes: 0) == "Release to cancel")
    }
}
