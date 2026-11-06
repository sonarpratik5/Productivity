import Testing
@testable import Productivity
import Foundation

// MARK: - Shared test helpers

private let epoch = Date(timeIntervalSinceReferenceDate: 0)

private func date(_ seconds: TimeInterval) -> Date {
    epoch.addingTimeInterval(seconds)
}

// MARK: - Timeline label resize UX

@Suite("Timeline label resize UX")
struct TimelineLabelResizeUXTests {

    private func baseline() -> (DateInterval, [TimelineLabelSegment]) {
        let interval = DateInterval(start: date(0), end: date(90))
        return (
            interval,
            [
                TimelineLabelSegment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, label: .productive, startDate: date(0), endDate: date(30)),
                TimelineLabelSegment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, label: .unproductive, startDate: date(30), endDate: date(60)),
                TimelineLabelSegment(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, label: .unknown, startDate: date(60), endDate: date(90))
            ]
        )
    }

    @Test("dragging leading edge left shrinks previous label immediately")
    func leadingEdgeLeftShrinksPreviousLabel() {
        let (interval, labels) = baseline()
        let changed = TimelineLabelSegment(id: labels[1].id, label: labels[1].label, startDate: date(20), endDate: date(60))

        let result = labelSegmentsByResizingBoundary(labels, changedSegment: changed, edge: .leading, in: interval)

        #expect(result[0].startDate == date(0))
        #expect(result[0].endDate == date(20))
        #expect(result[1].startDate == date(20))
        #expect(result[1].endDate == date(60))
    }

    @Test("dragging trailing edge right shrinks next label immediately")
    func trailingEdgeRightShrinksNextLabel() {
        let (interval, labels) = baseline()
        let changed = TimelineLabelSegment(id: labels[1].id, label: labels[1].label, startDate: date(30), endDate: date(70))

        let result = labelSegmentsByResizingBoundary(labels, changedSegment: changed, edge: .trailing, in: interval)

        #expect(result[1].startDate == date(30))
        #expect(result[1].endDate == date(70))
        #expect(result[2].startDate == date(70))
        #expect(result[2].endDate == date(90))
    }

    @Test("dragging trailing edge left expands next label immediately")
    func trailingEdgeLeftExpandsNextLabel() {
        let (interval, labels) = baseline()
        let changed = TimelineLabelSegment(id: labels[1].id, label: labels[1].label, startDate: date(30), endDate: date(50))

        let result = labelSegmentsByResizingBoundary(labels, changedSegment: changed, edge: .trailing, in: interval)

        #expect(result[1].startDate == date(30))
        #expect(result[1].endDate == date(50))
        #expect(result[2].startDate == date(50))
        #expect(result[2].endDate == date(90))
    }

    @Test("live resize output remains non-overlapping")
    func liveResizeOutputNonOverlapping() {
        let (interval, labels) = baseline()
        let changed = TimelineLabelSegment(id: labels[1].id, label: labels[1].label, startDate: date(10), endDate: date(85))

        let result = labelSegmentsByResizingBoundary(labels, changedSegment: changed, edge: .trailing, in: interval)

        for index in result.indices.dropLast() {
            #expect(result[index].endDate <= result[index + 1].startDate)
        }
    }
}

@Suite("Timeline label stored override composition")
struct TimelineLabelStoredOverrideCompositionTests {

    @Test("stored override does not replace unrelated derived labels with unknown")
    func storedOverrideKeepsDerivedLabelsOutsideEdit() {
        let interval = DateInterval(start: date(0), end: date(90))
        let derived = [
            TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(30)),
            TimelineLabelSegment(label: .unproductive, startDate: date(30), endDate: date(60)),
            TimelineLabelSegment(label: .productive, startDate: date(60), endDate: date(90))
        ]
        let stored = [TimelineLabelSegment(label: .unproductive, startDate: date(10), endDate: date(20))]

        let result = labelSegmentsByApplyingStoredOverrides(derivedSegments: derived, storedSegments: stored, in: interval)

        #expect(result.contains { $0.label == .productive && $0.startDate == date(0) && $0.endDate == date(10) })
        #expect(result.contains { $0.label == .unproductive && $0.startDate == date(10) && $0.endDate == date(20) })
        #expect(result.contains { $0.label == .unproductive && $0.startDate == date(30) && $0.endDate == date(60) })
        #expect(result.contains { $0.label == .productive && $0.startDate == date(60) && $0.endDate == date(90) })
    }

    @Test("unknown blanket stored label is preserved as a valid user edit")
    func unknownBlanketStoredLabelIsPreserved() {
        let interval = DateInterval(start: date(0), end: date(90))
        let derived = [
            TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(45)),
            TimelineLabelSegment(label: .unproductive, startDate: date(45), endDate: date(90))
        ]
        let stored = [TimelineLabelSegment(label: .unknown, startDate: date(0), endDate: date(90))]

        let result = labelSegmentsByApplyingStoredOverrides(derivedSegments: derived, storedSegments: stored, in: interval)

        #expect(result.count == 1)
        #expect(result[0].label == .unknown)
        #expect(result[0].startDate == date(0))
        #expect(result[0].endDate == date(90))
    }

    @Test("commit stores only labels that differ from derived labels")
    func overrideCommitStoresOnlyDifferences() {
        let interval = DateInterval(start: date(0), end: date(60))
        let derived = [TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(60))]
        let edited = [
            TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(20)),
            TimelineLabelSegment(label: .unproductive, startDate: date(20), endDate: date(40)),
            TimelineLabelSegment(label: .productive, startDate: date(40), endDate: date(60))
        ]

        let result = labelOverrideSegments(editedSegments: edited, derivedSegments: derived, in: interval)

        #expect(result.count == 1)
        #expect(result[0].label == .unproductive)
        #expect(result[0].startDate == date(20))
        #expect(result[0].endDate == date(40))
    }

    @Test("commit does not store label edits outside derived activity")
    func overrideCommitIgnoresGapsWithoutDerivedActivity() {
        let interval = DateInterval(start: date(0), end: date(120))
        let derived = [
            TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(30)),
            TimelineLabelSegment(label: .productive, startDate: date(90), endDate: date(120))
        ]
        let edited = [
            TimelineLabelSegment(label: .productive, startDate: date(0), endDate: date(30)),
            TimelineLabelSegment(label: .focus, startDate: date(30), endDate: date(90)),
            TimelineLabelSegment(label: .unproductive, startDate: date(90), endDate: date(120))
        ]

        let result = labelOverrideSegments(editedSegments: edited, derivedSegments: derived, in: interval)

        #expect(result.count == 1)
        #expect(result[0].label == .unproductive)
        #expect(result[0].startDate == date(90))
        #expect(result[0].endDate == date(120))
    }

    @Test("commit preserves stored overrides outside the visible edit window")
    func overrideCommitPreservesStoredOverridesOutsideEditedWindow() {
        let dayInterval = DateInterval(start: date(0), end: date(240))
        let editedInterval = DateInterval(start: date(120), end: date(180))
        let stored = [
            TimelineLabelSegment(label: .unproductive, startDate: date(30), endDate: date(60)),
            TimelineLabelSegment(label: .productive, startDate: date(100), endDate: date(140)),
            TimelineLabelSegment(label: .unknown, startDate: date(200), endDate: date(220))
        ]
        let current = [
            TimelineLabelSegment(label: .focus, startDate: date(150), endDate: date(170))
        ]

        let result = labelOverrideSegmentsForCommit(
            currentOverrideSegments: current,
            storedSegments: stored,
            editedInterval: editedInterval,
            dayInterval: dayInterval
        )

        #expect(result.contains { $0.label == .unproductive && $0.startDate == date(30) && $0.endDate == date(60) })
        #expect(result.contains { $0.label == .productive && $0.startDate == date(100) && $0.endDate == date(120) })
        #expect(result.contains { $0.label == .focus && $0.startDate == date(150) && $0.endDate == date(170) })
        #expect(result.contains { $0.label == .unknown && $0.startDate == date(200) && $0.endDate == date(220) })
        #expect(!result.contains { $0.label == .productive && $0.startDate == date(120) && $0.endDate == date(140) })
    }

    @Test("commit clamps stored overrides to the current day")
    func overrideCommitClampsStoredOverridesToCurrentDay() {
        let dayInterval = DateInterval(start: date(100), end: date(200))
        let editedInterval = DateInterval(start: date(140), end: date(160))
        let stored = [
            TimelineLabelSegment(label: .unproductive, startDate: date(80), endDate: date(120)),
            TimelineLabelSegment(label: .unknown, startDate: date(180), endDate: date(220))
        ]

        let result = labelOverrideSegmentsForCommit(
            currentOverrideSegments: [],
            storedSegments: stored,
            editedInterval: editedInterval,
            dayInterval: dayInterval
        )

        #expect(result.count == 2)
        #expect(result.contains { $0.label == .unproductive && $0.startDate == date(100) && $0.endDate == date(120) })
        #expect(result.contains { $0.label == .unknown && $0.startDate == date(180) && $0.endDate == date(200) })
    }
}

@Suite("Weekly insight label correction")
struct WeeklyInsightLabelCorrectionTests {

    @Test("stored label starting before activity is clipped to derived activity")
    func storedLabelStartingBeforeActivityIsClipped() {
        let segments = [
            segment(start: 100, end: 200, category: .focus)
        ]
        let labels = [
            TimelineLabelSegment(label: .unproductive, startDate: date(50), endDate: date(150))
        ]

        let result = weeklyLabelCorrectedSegments(from: segments, labelSegments: labels)

        #expect(result.count == 2)
        #expect(result.contains { $0.label == .unproductive && $0.startDate == date(100) && $0.endDate == date(150) })
        #expect(result.contains { $0.label == .focus && $0.startDate == date(150) && $0.endDate == date(200) })
    }

    @Test("stored labels without derived activity are ignored")
    func storedLabelWithoutDerivedActivityIsIgnored() {
        let segments = [
            segment(start: 0, end: 30, category: .focus)
        ]
        let labels = [
            TimelineLabelSegment(label: .unproductive, startDate: date(60), endDate: date(90))
        ]

        let result = weeklyLabelCorrectedSegments(from: segments, labelSegments: labels)

        #expect(result.count == 1)
        #expect(result[0].label == .focus)
        #expect(result[0].startDate == date(0))
        #expect(result[0].endDate == date(30))
    }
}

private func segment(
    start: TimeInterval,
    end: TimeInterval,
    score: Double = 0.5,
    category: ActivityCategory = .focus,
    appName: String = "TestApp",
    bundleID: String = "com.test.app",
    companion: Bool = false,
    lifecycle: Bool = false
) -> ActivitySegment {
    ActivitySegment(
        appName: appName,
        bundleIdentifier: lifecycle ? "productivity.lifecycle.opened" : bundleID,
        title: appName,
        userDescription: companion ? "Background companion activity" : nil,
        startDate: date(start),
        endDate: date(end),
        category: category,
        productivityScore: score
    )
}

private func label(
    start: TimeInterval,
    end: TimeInterval,
    label: ActivityLabel = .productive
) -> TimelineLabelSegment {
    TimelineLabelSegment(label: label, startDate: date(start), endDate: date(end))
}

// MARK: - TimelineLabelSegment.normalized

@Suite("TimelineLabelSegment.normalized")
struct NormalizedLabelTests {

    @Test("empty input → empty output")
    func emptyInput() {
        #expect(TimelineLabelSegment.normalized([]).isEmpty)
    }

    @Test("zero-duration segment is dropped")
    func zeroDurationDropped() {
        let result = TimelineLabelSegment.normalized([label(start: 0, end: 0)])
        #expect(result.isEmpty)
    }

    @Test("negative-duration segment is dropped")
    func negativeDurationDropped() {
        let result = TimelineLabelSegment.normalized([label(start: 60, end: 0)])
        #expect(result.isEmpty)
    }

    @Test("single valid segment passes through unchanged")
    func singlePassThrough() {
        let result = TimelineLabelSegment.normalized([label(start: 0, end: 60)])
        #expect(result.count == 1)
        #expect(result[0].duration == 60)
    }

    @Test("single valid segment preserves identity")
    func singleSegmentPreservesIdentity() {
        let id = UUID(uuidString: "12121212-1212-1212-1212-121212121212")!
        let input = TimelineLabelSegment(id: id, label: .productive, startDate: date(0), endDate: date(60))

        let result = TimelineLabelSegment.normalized([input])

        #expect(result.first?.id == id)
    }

    @Test("non-overlapping segments pass through in order")
    func nonOverlappingPreserved() {
        let input = [
            label(start: 0,  end: 30,  label: .productive),
            label(start: 30, end: 60,  label: .unproductive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 2)
        #expect(result[0].label == .productive)
        #expect(result[1].label == .unproductive)
    }

    @Test("adjacent same-label segments are merged into one")
    func adjacentSameLabelMerged() {
        let input = [
            label(start: 0,  end: 30, label: .productive),
            label(start: 30, end: 60, label: .productive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 1)
        #expect(result[0].duration == 60)
        #expect(result[0].label == .productive)
    }

    @Test("adjacent different-label segments are NOT merged")
    func adjacentDifferentLabelNotMerged() {
        let input = [
            label(start: 0,  end: 30, label: .productive),
            label(start: 30, end: 60, label: .unknown)
        ]
        let result = TimelineLabelSegment.normalized(input)
        #expect(result.count == 2)
    }

    @Test("overlapping segments: later-started segment wins")
    func overlappingLaterStartWins() {
        // [----productive 0-60----]
        //         [--unproductive 30-90--]
        let input = [
            label(start: 0,  end: 60, label: .productive),
            label(start: 30, end: 90, label: .unproductive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        // Expected: [0-30 productive] [30-90 unproductive]
        #expect(result.count == 2)
        #expect(result[0].label == .productive)
        #expect(result[0].duration == 30)
        #expect(result[1].label == .unproductive)
        #expect(result[1].duration == 60)
    }

    @Test("fully-contained segment: inner wins for its range, outer fills around it")
    func fullyContainedInnerWins() {
        // [--------productive 0-90--------]
        //      [--unproductive 30-60--]
        let input = [
            label(start: 0,  end: 90, label: .productive),
            label(start: 30, end: 60, label: .unproductive)
        ]
        let result = TimelineLabelSegment.normalized(input)
        // Expected: [0-30 productive] [30-60 unproductive] [60-90 productive]
        #expect(result.count == 3)
        #expect(result[0].label == .productive && result[0].duration == 30)
        #expect(result[1].label == .unproductive && result[1].duration == 30)
        #expect(result[2].label == .productive && result[2].duration == 30)
    }

    @Test("three overlapping segments: last wins where all overlap")
    func threeOverlappingLastWins() {
        let input = [
            label(start: 0,  end: 90, label: .productive),
            label(start: 30, end: 90, label: .unproductive),
            label(start: 60, end: 90, label: .unknown)
        ]
        let result = TimelineLabelSegment.normalized(input)
        let lastSegment = result.last
        #expect(lastSegment?.label == .unknown)
        #expect(lastSegment?.duration == 30)
    }

    @Test("output segments are non-overlapping")
    func outputNonOverlapping() {
        let input = [
            label(start: 0,  end: 60, label: .productive),
            label(start: 20, end: 80, label: .unproductive),
            label(start: 40, end: 100, label: .unknown)
        ]
        let result = TimelineLabelSegment.normalized(input)
        for i in result.indices.dropLast() {
            #expect(result[i].endDate <= result[i + 1].startDate,
                    "Segments must not overlap: index \(i) ends after \(i+1) starts")
        }
    }

    @Test("total duration never exceeds input span")
    func totalDurationBounded() {
        let input = [
            label(start: 0,  end: 60, label: .productive),
            label(start: 0,  end: 60, label: .unproductive),
            label(start: 0,  end: 60, label: .unknown)
        ]
        let result = TimelineLabelSegment.normalized(input)
        let totalDuration = result.reduce(0) { $0 + $1.duration }
        #expect(totalDuration <= 60 + 0.001)
    }
}

// MARK: - ActivitySegment.primaryAttentionSegments

@Suite("ActivitySegment.primaryAttentionSegments")
struct PrimaryAttentionTests {

    @Test("empty input → empty output")
    func emptyInput() {
        #expect(ActivitySegment.primaryAttentionSegments(from: []).isEmpty)
    }

    @Test("companion context segments are excluded")
    func companionExcluded() {
        let result = ActivitySegment.primaryAttentionSegments(from: [
            segment(start: 0, end: 60, companion: true)
        ])
        #expect(result.isEmpty)
    }

    @Test("lifecycle context segments are excluded")
    func lifecycleExcluded() {
        let result = ActivitySegment.primaryAttentionSegments(from: [
            segment(start: 0, end: 60, lifecycle: true)
        ])
        #expect(result.isEmpty)
    }

    @Test("single non-overlapping segment passes through")
    func singleSegment() {
        let result = ActivitySegment.primaryAttentionSegments(from: [
            segment(start: 0, end: 60)
        ])
        #expect(result.count == 1)
        #expect(abs(result[0].duration - 60) < 0.001)
    }

    @Test("non-overlapping segments: total duration preserved")
    func nonOverlappingTotalDuration() {
        let input = [
            segment(start: 0,  end: 30, appName: "A"),
            segment(start: 30, end: 60, appName: "B")
        ]
        let result = ActivitySegment.primaryAttentionSegments(from: input)
        let total = result.reduce(0) { $0 + $1.duration }
        #expect(abs(total - 60) < 0.001)
    }

    @Test("overlapping segments: higher productivity score dominates")
    func higherScoreDominates() {
        // Low score occupies 0-60, high score occupies 20-40
        let low  = segment(start: 0,  end: 60, score: 0.1, appName: "Low")
        let high = segment(start: 20, end: 40, score: 0.9, appName: "High")
        let result = ActivitySegment.primaryAttentionSegments(from: [low, high])
        let highDuration = result.filter { $0.appName == "High" }.reduce(0) { $0 + $1.duration }
        #expect(abs(highDuration - 20) < 0.001)
    }

    @Test("completely identical overlapping segments: total duration = single span")
    func identicalOverlapBounded() {
        let a = segment(start: 0, end: 60, score: 0.5, appName: "A", bundleID: "com.a")
        let b = segment(start: 0, end: 60, score: 0.5, appName: "B", bundleID: "com.b")
        let result = ActivitySegment.primaryAttentionSegments(from: [a, b])
        let total = result.reduce(0) { $0 + $1.duration }
        #expect(total <= 60 + 0.001)
    }

    @Test("output has no time gaps across a continuous input range")
    func noContinuityGaps() {
        let a = segment(start: 0,  end: 40, score: 0.5, appName: "A")
        let b = segment(start: 20, end: 60, score: 0.3, appName: "B")
        let result = ActivitySegment.primaryAttentionSegments(from: [a, b]).sorted { $0.startDate < $1.startDate }
        for i in result.indices.dropLast() {
            #expect(result[i].endDate == result[i + 1].startDate,
                    "Gap between segment \(i) and \(i+1)")
        }
    }

    @Test("output segments are always non-overlapping")
    func outputNonOverlapping() {
        let input = [
            segment(start: 0,  end: 90, score: 0.2, appName: "A"),
            segment(start: 10, end: 60, score: 0.8, appName: "B"),
            segment(start: 40, end: 80, score: 0.5, appName: "C")
        ]
        let result = ActivitySegment.primaryAttentionSegments(from: input).sorted { $0.startDate < $1.startDate }
        for i in result.indices.dropLast() {
            #expect(result[i].endDate <= result[i + 1].startDate,
                    "Overlap between segment \(i) and \(i+1)")
        }
    }

    @Test("companion context does not appear in primary output even when co-present")
    func companionNotInPrimary() {
        let primary   = segment(start: 0, end: 60, appName: "Xcode")
        let companion = segment(start: 0, end: 60, appName: "Spotify", companion: true)
        let result = ActivitySegment.primaryAttentionSegments(from: [primary, companion])
        #expect(result.allSatisfy { $0.appName != "Spotify" })
    }
}

// MARK: - TimelineLabelSegment.derived

@Suite("TimelineLabelSegment.derived")
struct DerivedLabelTests {

    @Test("empty input → empty output")
    func emptyInput() {
        #expect(TimelineLabelSegment.derived(from: []).isEmpty)
    }

    @Test("companion-only input → empty output")
    func companionOnlyEmpty() {
        let result = TimelineLabelSegment.derived(from: [
            segment(start: 0, end: 60, appName: "Spotify", companion: true)
        ])
        #expect(result.isEmpty)
    }

    @Test("focus segment → focus label")
    func focusSegmentKeepsSpecificLabel() {
        let result = TimelineLabelSegment.derived(from: [
            segment(start: 0, end: 60, score: 0.9, category: .focus)
        ])
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.label == .focus })
    }

    @Test("custom productive segment keeps custom label")
    func customProductiveSegmentKeepsCustomLabel() {
        activityLabelCatalogTestLock.lock()
        let previousDefinitions = ActivityLabelCatalog.customDefinitions()
        let customLabel = ActivityLabel.custom("custom.test.deep-work")
        ActivityLabelCatalog.saveCustomDefinitions([
            ActivityLabelDefinition(
                id: customLabel.id,
                title: "Deep Work",
                systemImage: "scope",
                tint: ActivityLabelColor(red: 0.2, green: 0.7, blue: 0.6),
                rollup: .productive
            )
        ])
        defer {
            ActivityLabelCatalog.saveCustomDefinitions(previousDefinitions)
            activityLabelCatalogTestLock.unlock()
        }

        let result = TimelineLabelSegment.derived(from: [
            ActivitySegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                title: "Xcode",
                startDate: date(0),
                endDate: date(60),
                category: customLabel.category,
                label: customLabel,
                productivityScore: customLabel.productivityScore
            )
        ])

        #expect(result.count == 1)
        #expect(result.first?.label == customLabel)
        #expect(result.first?.label.commonRollup == .productive)
    }

    @Test("entertainment segment → unproductive label")
    func entertainmentGivesUnproductiveLabel() {
        let result = TimelineLabelSegment.derived(from: [
            segment(start: 0, end: 60, score: 0.05, category: .entertainment)
        ])
        #expect(result.allSatisfy { $0.label == .unproductive })
    }

    @Test("derived labels cover the full input span")
    func labelsCoversSpan() {
        let result = TimelineLabelSegment.derived(from: [
            segment(start: 0, end: 60)
        ])
        let covered = result.reduce(0) { $0 + $1.duration }
        #expect(abs(covered - 60) < 0.001)
    }
}

// MARK: - TimelineStream.packed

@Suite("TimelineStream.packed")
struct TimelineStreamTests {

    @Test("empty input → empty streams")
    func emptyInput() {
        #expect(TimelineStream.packed(from: []).isEmpty)
    }

    @Test("only primary (non-companion) segments → stream 1 is primary attention lane")
    func primarySegmentIsStream1() {
        let result = TimelineStream.packed(from: [
            segment(start: 0, end: 60, appName: "Xcode")
        ])
        #expect(result.first?.number == 1)
    }

    @Test("non-overlapping companions fit in a single extra lane")
    func nonOverlappingCompanionsSingleLane() {
        let input = [
            segment(start: 0,  end: 60, appName: "Xcode"),
            segment(start: 0,  end: 30, appName: "Music",    bundleID: "com.apple.Music",    companion: true),
            segment(start: 30, end: 60, appName: "Podcasts", bundleID: "com.apple.podcasts", companion: true)
        ]
        let streams = TimelineStream.packed(from: input)
        // Stream 1 = primary attention, stream 2 = companion lane (fits both non-overlapping)
        #expect(streams.count <= 2)
    }

    @Test("overlapping companions are packed into separate lanes")
    func overlappingCompanionsSeparateLanes() {
        let input = [
            segment(start: 0, end: 60, appName: "Xcode"),
            segment(start: 0, end: 60, appName: "Music",    bundleID: "com.apple.Music",    companion: true),
            segment(start: 0, end: 60, appName: "Podcasts", bundleID: "com.apple.podcasts", companion: true)
        ]
        let streams = TimelineStream.packed(from: input)
        // At minimum: stream 1 primary + stream 2 companion 1 + stream 3 companion 2
        #expect(streams.count >= 3)
    }

    @Test("stream numbers are contiguous starting from 1")
    func streamNumbersContiguous() {
        let input = [
            segment(start: 0, end: 60, appName: "Xcode"),
            segment(start: 0, end: 60, appName: "Music", bundleID: "com.apple.Music", companion: true)
        ]
        let numbers = TimelineStream.packed(from: input).map(\.number)
        for (index, number) in numbers.enumerated() {
            #expect(number == index + 1)
        }
    }
}
