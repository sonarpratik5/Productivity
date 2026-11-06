import AppKit
import SwiftUI

struct TimelineEditorView: View {
    let segments: [ActivitySegment]
    let events: [ManualActivityEvent]
    let storedLabelSegments: [TimelineLabelSegment]
    let onAddEvent: (ManualActivityEvent) -> Void
    let onUpdateEvent: (ManualActivityEvent) -> Void
    let onDeleteEvent: (ManualActivityEvent) -> Void
    let onLabelSegmentsChange: ([TimelineLabelSegment]) -> Void

    @State private var editableLabelSegments: [TimelineLabelSegment] = []
    @State private var editSessionBaseline: [TimelineLabelSegment] = []
    @State private var editSessionInterval: DateInterval? = nil
    @State private var editSessionStreamSegments: [ActivitySegment] = []
    @State private var isAddEventPresented = false
    @State private var isEventsPopoverPresented = false
    @State private var isEditingLabels = false
    @State private var isHoveringTimelineScroll = false
    @State private var editingEvent: ManualActivityEvent?
    @State private var timelineLookbackOffset: TimeInterval = 0
    @State private var sourceFingerprint: Int?
    @AppStorage(TrackingPreferenceKeys.timelineHorizonSeconds) private var timelineHorizonSeconds = TrackingPreferences.recommendedTimelineHorizonSeconds
    @AppStorage(TrackingPreferenceKeys.isTimelineEventContextOverlayEnabled) private var isTimelineEventContextOverlayEnabled = true
    @AppStorage(TrackingPreferenceKeys.isSleepHiddenInDayProgress) private var isSleepHiddenInDayProgress = true

    private var timelineSnapshot: TimelineRenderSnapshot {
        let dayInterval = dayInterval
        let streamViewInterval = streamViewInterval(for: dayInterval)
        var streamSegments: [ActivitySegment] = []
        var streamEventContextSegments: [ActivitySegment] = []
        var dayProgressSegments: [ActivitySegment] = []

        for segment in segments {
            if segment.isDayProgressEvent,
               let dayProgressSegment = clippedSegment(segment, to: dayInterval) {
                dayProgressSegments.append(dayProgressSegment)
            }

            guard let streamSegment = clippedSegment(segment, to: streamViewInterval) else { continue }
            if segment.isManualEventContext {
                streamEventContextSegments.append(streamSegment)
            } else {
                streamSegments.append(streamSegment)
            }
        }

        return TimelineRenderSnapshot(
            dayInterval: dayInterval,
            streamViewInterval: streamViewInterval,
            streamSegments: streamSegments,
            streamEventContextSegments: streamEventContextSegments,
            dayProgressSegments: dayProgressSegments,
            streams: TimelineStream.packed(from: streamSegments)
        )
    }

    private var dayInterval: DateInterval {
        Calendar.current.dateInterval(of: .day, for: Date())
            ?? DateInterval(start: Calendar.current.startOfDay(for: Date()), duration: 24 * 60 * 60)
    }

    private func derivedLabelSegments(from streamSegments: [ActivitySegment]) -> [TimelineLabelSegment] {
        TimelineLabelSegment.derived(from: streamSegments)
    }

    private var interval: DateInterval? {
        streamViewInterval
    }

    private var streamViewInterval: DateInterval {
        streamViewInterval(for: dayInterval)
    }

    private func streamViewInterval(for dayInterval: DateInterval) -> DateInterval {
        let latestDate = min(dayInterval.end, Date())
        let endDate = max(dayInterval.start, latestDate.addingTimeInterval(-timelineLookbackOffset))
        let startDate = max(dayInterval.start, endDate.addingTimeInterval(-streamWindowDuration))
        return DateInterval(start: startDate, end: endDate)
    }

    private var streamWindowDuration: TimeInterval {
        min(max(timelineHorizonSeconds, 10 * 60), 60 * 60)
    }

    private var canMoveTimelineBack: Bool {
        streamViewInterval.start > dayInterval.start
    }

    private var canMoveTimelineForward: Bool {
        timelineLookbackOffset > 1
    }

    private var currentSourceFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(segments.count)
        for segment in segments {
            hasher.combine(segment)
        }
        hasher.combine(storedLabelSegments.count)
        for segment in storedLabelSegments {
            hasher.combine(segment)
        }
        return hasher.finalize()
    }

    var body: some View {
        let snapshot = timelineSnapshot

        GeometryReader { proxy in
            let showsLabelLane = showsLabelLane(for: snapshot)
            let metrics = TimelineMetrics(width: proxy.size.width)
            let trackViewportWidth = timelineTrackWidth(for: proxy.size.width, metrics: metrics)
            let trackMetrics = TimelineMetrics(width: trackViewportWidth)

            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                HStack(spacing: 10) {
                    Label("Activity Timeline", systemImage: "timeline.selection")
                        .productivityFont(.sectionLabel)

                    Spacer()

                    Button {
                        isEventsPopoverPresented = true
                    } label: {
                        Label("View Events", systemImage: "calendar")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("View, edit, or delete manual events")
                    .popover(isPresented: $isEventsPopoverPresented, arrowEdge: .bottom) {
                        ManualEventsListView(
                            events: events,
                            onEdit: { event in
                                isEventsPopoverPresented = false
                                editingEvent = event
                            },
                            onDelete: onDeleteEvent
                        )
                    }

                    Button {
                        isAddEventPresented = true
                    } label: {
                        Label("Add Event", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Add a manual event to today")
                    .popover(isPresented: $isAddEventPresented, arrowEdge: .bottom) {
                        ManualActivityEventForm(
                            dayInterval: dayInterval,
                            onSave: { event in
                                onAddEvent(event)
                                isAddEventPresented = false
                            },
                            onCancel: {
                                isAddEventPresented = false
                            }
                        )
                    }

                    Button {
                        toggleLabelEditing()
                    } label: {
                        Label(isEditingLabels ? "Done" : "Edit Labels", systemImage: isEditingLabels ? "checkmark" : "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Toggle manual label editing")

                    if canMoveTimelineForward {
                        Button {
                            withAnimation(.smooth(duration: 0.3)) {
                                timelineLookbackOffset = 0
                            }
                        } label: {
                            Label("Now", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Jump to the current moment")
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }

                    Text("\(snapshot.streams.count) streams · \(snapshot.streamSegments.count) clips")
                        .productivityFont(.note)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                TimelineDayProgressView(
                    dayInterval: snapshot.dayInterval,
                    segments: snapshot.dayProgressSegments,
                    hidesSleep: isSleepHiddenInDayProgress
                )

                HStack(alignment: .top, spacing: 14) {
                    TimelineLabelColumnView(streams: snapshot.streams, metrics: metrics, showsLabelLane: showsLabelLane)

                    ZStack {
                        if isTimelineEventContextOverlayEnabled {
                            TimelineEventContextOverlay(
                                segments: snapshot.streamEventContextSegments,
                                interval: snapshot.streamViewInterval,
                                metrics: trackMetrics,
                                streamCount: snapshot.streams.count
                            )
                            .frame(width: trackViewportWidth, height: timelineTrackHeight(streamCount: snapshot.streams.count, showsLabelLane: showsLabelLane, metrics: metrics))
                            .allowsHitTesting(false)
                        }

                        VStack(spacing: metrics.laneSpacing) {
                            TimelineRulerTrackView(interval: snapshot.streamViewInterval, metrics: trackMetrics)
                                .frame(width: trackViewportWidth, height: 28)

                            ForEach(snapshot.streams) { stream in
                                TimelineStreamTrackView(stream: stream, interval: snapshot.streamViewInterval, metrics: trackMetrics)
                                    .frame(width: trackViewportWidth, height: metrics.laneHeight)
                            }

                            if showsLabelLane {
                                TimelineLabelTrackView(
                                    labelSegments: $editableLabelSegments,
                                    baselineSegments: $editSessionBaseline,
                                    interval: snapshot.streamViewInterval,
                                    metrics: trackMetrics,
                                    isEditingEnabled: isEditingLabels,
                                    onCommit: onLabelSegmentsChange
                                )
                                .frame(width: trackViewportWidth, height: metrics.laneHeight)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .animation(.easeInOut(duration: 0.5), value: timelineLookbackOffset)

                        if isHoveringTimelineScroll && canMoveTimelineBack {
                            TimelineScrollArrow(systemName: "chevron.left", help: "Move earlier in today") {
                                moveTimelineBack()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                            .offset(x: 6)
                        }

                        if isHoveringTimelineScroll && canMoveTimelineForward {
                            TimelineScrollArrow(systemName: "chevron.right", help: "Move back toward now") {
                                moveTimelineForward()
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                            .offset(x: -6)
                        }
                    }
                    .frame(width: trackViewportWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringTimelineScroll = hovering
                    }
                }
            }
            .padding(metrics.panelPadding)
            .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
        }
        .frame(minHeight: timelineHeight(streamCount: snapshot.streams.count, showsLabelLane: showsLabelLane(for: snapshot)))
        .onAppear {
            syncEditableLabelsIfNeeded()
        }
        .onChange(of: currentSourceFingerprint) { _, _ in
            syncEditableLabelsIfNeeded(force: true)
            // Only snap to 0 when the offset has drifted slightly (< 1s) but isn't already 0,
            // to avoid writing the same value and re-triggering onChange(of: timelineLookbackOffset).
            if timelineLookbackOffset > 0, timelineLookbackOffset < 1 {
                timelineLookbackOffset = 0
            }
        }
        .onChange(of: timelineLookbackOffset) { _, _ in
            syncEditableLabelsIfNeeded(force: true)
        }
        .sheet(item: $editingEvent) { event in
            ManualActivityEventForm(
                event: event,
                dayInterval: dayInterval,
                onSave: { updatedEvent in
                    onUpdateEvent(updatedEvent)
                    editingEvent = nil
                },
                onCancel: {
                    editingEvent = nil
                }
            )
            .frame(width: 520)
        }
    }

    private func timelineHeight(streamCount: Int, showsLabelLane: Bool) -> CGFloat {
        let laneCount = streamCount + (showsLabelLane ? 1 : 0)
        return 176 + CGFloat(laneCount * 40)
    }

    private func timelineTrackHeight(streamCount: Int, showsLabelLane: Bool, metrics: TimelineMetrics) -> CGFloat {
        let laneCount = streamCount + (showsLabelLane ? 1 : 0)
        guard laneCount > 0 else { return 28 }
        return 28 + CGFloat(laneCount) * (metrics.laneHeight + metrics.laneSpacing)
    }

    private func timelineTrackWidth(for width: CGFloat, metrics: TimelineMetrics) -> CGFloat {
        max(0, width - metrics.labelWidth - metrics.panelPadding * 2 - 14)
    }

    private func showsLabelLane(for snapshot: TimelineRenderSnapshot) -> Bool {
        // Only show the label lane when there is real app activity in the window.
        // Stored labels alone (no stream segments) must not force the lane open —
        // they get incorporated into editableLabelSegments by syncEditableLabelsIfNeeded,
        // which already guards against empty stream windows.
        !snapshot.streamSegments.isEmpty || !editableLabelSegments.isEmpty
    }

    private func moveTimelineBack() {
        let step = max(5 * 60.0, streamWindowDuration * 0.6)
        let maximumLookback = max(0, min(Date(), dayInterval.end).timeIntervalSince(dayInterval.start) - streamWindowDuration)
        withAnimation(.easeInOut(duration: 0.55)) {
            timelineLookbackOffset = min(maximumLookback, timelineLookbackOffset + step)
        }
    }

    private func moveTimelineForward() {
        let step = max(5 * 60.0, streamWindowDuration * 0.6)
        withAnimation(.easeInOut(duration: 0.55)) {
            timelineLookbackOffset = max(0, timelineLookbackOffset - step)
        }
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

    private func syncEditableLabelsIfNeeded(force: Bool = false) {
        let fingerprint = currentSourceFingerprint
        guard force || sourceFingerprint != fingerprint || editableLabelSegments.isEmpty else { return }
        guard !isEditingLabels else { return }
        let snapshot = timelineSnapshot
        sourceFingerprint = fingerprint

        // Don't fill the label lane with Unknown/stored labels when there is no tracked
        // app activity in the current window — it only creates confusing phantom labels.
        guard !snapshot.streamSegments.isEmpty else {
            editableLabelSegments = []
            editSessionBaseline = []
            return
        }

        let derivedSegments = derivedLabelSegments(from: snapshot.streamSegments)
        let sourceSegments = labelSegmentsByApplyingStoredOverrides(
            derivedSegments: derivedSegments,
            storedSegments: storedLabelSegments,
            in: snapshot.streamViewInterval
        )
        guard !sourceSegments.isEmpty else {
            editableLabelSegments = []
            editSessionBaseline = []
            return
        }

        // Reuse existing UUIDs where the label and start time match so ForEach treats
        // them as the same element across resyncs, preventing the entry/exit transition
        // flicker that looks like labels "moving back and forth".
        let previous = editableLabelSegments
        editableLabelSegments = sourceSegments.map { newSeg in
            if let existing = previous.first(where: {
                $0.label == newSeg.label &&
                abs($0.startDate.timeIntervalSince(newSeg.startDate)) < 1.0
            }) {
                return TimelineLabelSegment(id: existing.id, label: newSeg.label, startDate: newSeg.startDate, endDate: newSeg.endDate)
            }
            return newSeg
        }
        editSessionBaseline = editableLabelSegments
    }

    private func toggleLabelEditing() {
        withAnimation(.smooth(duration: 0.18)) {
            if isEditingLabels {
                // Use the interval and segments captured at edit-start so that
                // scrolling the timeline window during editing never causes the
                // commit to run against a different time range and corrupt labels.
                let commitInterval = editSessionInterval ?? streamViewInterval
                let commitStreamSegments = editSessionStreamSegments.isEmpty
                    ? timelineSnapshot.streamSegments
                    : editSessionStreamSegments
                mergeEditableLabels()
                normalizeEditableLabelsToCurrentInterval(in: commitInterval)
                let snapshot = timelineSnapshot
                let derivedSegments = derivedLabelSegments(from: commitStreamSegments)
                let overrideSegments = labelOverrideSegments(
                    editedSegments: editableLabelSegments,
                    derivedSegments: derivedSegments,
                    in: commitInterval
                )
                let updatedOverrideSegments = labelOverrideSegmentsForCommit(
                    currentOverrideSegments: overrideSegments,
                    storedSegments: storedLabelSegments,
                    editedInterval: commitInterval,
                    dayInterval: snapshot.dayInterval
                )
                editSessionBaseline = editableLabelSegments
                editSessionInterval = nil
                editSessionStreamSegments = []
                onLabelSegmentsChange(updatedOverrideSegments)
                isEditingLabels = false
            } else {
                let snapshot = timelineSnapshot
                editSessionBaseline = editableLabelSegments
                editSessionInterval = snapshot.streamViewInterval
                editSessionStreamSegments = snapshot.streamSegments
                isEditingLabels = true
            }
        }
    }

    private func mergeEditableLabels() {
        let sortedSegments = editableLabelSegments.sorted { $0.startDate < $1.startDate }
        var mergedSegments: [TimelineLabelSegment] = []

        for segment in sortedSegments where segment.duration > 0 {
            if let lastSegment = mergedSegments.last,
               lastSegment.label == segment.label,
               abs(lastSegment.endDate.timeIntervalSince(segment.startDate)) < 0.5 {
                mergedSegments.removeLast()
                mergedSegments.append(TimelineLabelSegment(
                    id: lastSegment.id,
                    label: lastSegment.label,
                    startDate: lastSegment.startDate,
                    endDate: segment.endDate
                ))
            } else {
                mergedSegments.append(segment)
            }
        }

        editableLabelSegments = mergedSegments
    }

    private func normalizeEditableLabelsToCurrentInterval(in currentInterval: DateInterval? = nil) {
        guard let interval = currentInterval ?? interval else { return }
        editableLabelSegments = normalizedLabelCoverage(editableLabelSegments, in: interval)
    }
}

private struct TimelineRenderSnapshot {
    let dayInterval: DateInterval
    let streamViewInterval: DateInterval
    let streamSegments: [ActivitySegment]
    let streamEventContextSegments: [ActivitySegment]
    let dayProgressSegments: [ActivitySegment]
    let streams: [TimelineStream]
}

private struct TimelineMetrics {
    let width: CGFloat

    var panelPadding: CGFloat {
        width < 620 ? 14 : 18
    }

    var labelWidth: CGFloat {
        if width < 540 { return 72 }
        if width < 760 { return 88 }
        return 104
    }

    var laneSpacing: CGFloat {
        width < 620 ? 6 : 8
    }

    var sectionSpacing: CGFloat {
        width < 620 ? 12 : 14
    }

    var laneHeight: CGFloat {
        width < 620 ? 24 : 30
    }

    var clipHeight: CGFloat {
        width < 620 ? 18 : 22
    }

    var timelinePixelsPerHour: CGFloat {
        width < 620 ? 132 : 168
    }

    var tickCount: Int {
        if width < 520 { return 3 }
        if width < 820 { return 4 }
        return 5
    }

    var tickOffsets: [Double] {
        guard tickCount > 1 else { return [0] }
        return (0..<tickCount).map { Double($0) / Double(tickCount - 1) }
    }
}

private struct TimelineScrollArrow: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .frame(width: 26, height: 42)
                .background(ProductivityTheme.elevatedBackground.opacity(0.9), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(ProductivityTheme.border.opacity(0.48), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

private func normalizedLabelCoverage(_ segments: [TimelineLabelSegment], in interval: DateInterval) -> [TimelineLabelSegment] {
    let clampedSegments = segments.compactMap { segment -> TimelineLabelSegment? in
        guard segment.endDate > segment.startDate else { return nil }
        let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
        guard interval.intersects(segmentInterval) else { return nil }
        let startDate = max(segment.startDate, interval.start)
        let endDate = min(segment.endDate, interval.end)
        guard endDate > startDate else { return nil }
        return TimelineLabelSegment(
            id: segment.id,
            label: segment.label,
            startDate: startDate,
            endDate: endDate
        )
    }
    .sorted {
        if $0.startDate == $1.startDate {
            return $0.endDate < $1.endDate
        }

        return $0.startDate < $1.startDate
    }

    var normalizedSegments: [TimelineLabelSegment] = []
    var cursor = interval.start

    for segment in clampedSegments {
        if segment.startDate > cursor {
            appendLabelSegment(
                TimelineLabelSegment(label: .unknown, startDate: cursor, endDate: segment.startDate),
                to: &normalizedSegments
            )
        }

        let startDate = max(segment.startDate, cursor)
        let endDate = max(startDate, segment.endDate)
        if endDate > startDate {
            appendLabelSegment(
                TimelineLabelSegment(
                    id: segment.id,
                    label: segment.label,
                    startDate: startDate,
                    endDate: endDate
                ),
                to: &normalizedSegments
            )
            cursor = endDate
        }
    }

    if cursor < interval.end {
        appendLabelSegment(
            TimelineLabelSegment(label: .unknown, startDate: cursor, endDate: interval.end),
            to: &normalizedSegments
        )
    }

    return normalizedSegments
}

private func appendLabelSegment(_ segment: TimelineLabelSegment, to segments: inout [TimelineLabelSegment]) {
    guard segment.endDate > segment.startDate else { return }
    if let lastSegment = segments.last,
       lastSegment.label == segment.label,
       abs(lastSegment.endDate.timeIntervalSince(segment.startDate)) < 0.5 {
        segments.removeLast()
        segments.append(TimelineLabelSegment(
            id: lastSegment.id,
            label: lastSegment.label,
            startDate: lastSegment.startDate,
            endDate: segment.endDate
        ))
    } else {
        segments.append(segment)
    }
}

func labelSegmentsByApplyingStoredOverrides(
    derivedSegments: [TimelineLabelSegment],
    storedSegments: [TimelineLabelSegment],
    in interval: DateInterval
) -> [TimelineLabelSegment] {
    let baseSegments = normalizedLabelCoverage(derivedSegments, in: interval)
    let clippedStoredSegments = storedSegments.compactMap { segment in
        clippedLabelSegment(segment, to: interval)
    }
    let overrideSegments = TimelineLabelSegment.normalized(clippedStoredSegments)
    guard !overrideSegments.isEmpty else { return baseSegments }

    return labelSegmentsBySlicing(
        interval: interval,
        baseSegments: baseSegments,
        overrideSegments: overrideSegments,
        preferOverride: true
    )
}

func labelOverrideSegments(
    editedSegments: [TimelineLabelSegment],
    derivedSegments: [TimelineLabelSegment],
    in interval: DateInterval
) -> [TimelineLabelSegment] {
    let editedCoverage = normalizedLabelCoverage(editedSegments, in: interval)
    let derivedCoverage = TimelineLabelSegment.normalized(derivedSegments.compactMap {
        clippedLabelSegment($0, to: interval)
    })

    return labelSegmentsBySlicing(
        interval: interval,
        baseSegments: derivedCoverage,
        overrideSegments: editedCoverage,
        preferOverride: false
    )
}

func labelOverrideSegmentsForCommit(
    currentOverrideSegments: [TimelineLabelSegment],
    storedSegments: [TimelineLabelSegment],
    editedInterval: DateInterval,
    dayInterval: DateInterval
) -> [TimelineLabelSegment] {
    let retainedStoredSegments = storedSegments
        .flatMap { labelSegments(of: $0, outside: editedInterval) }
        .compactMap { clippedLabelSegment($0, to: dayInterval) }
    let clampedCurrentSegments = currentOverrideSegments.compactMap { clippedLabelSegment($0, to: dayInterval) }
    return TimelineLabelSegment.normalized(retainedStoredSegments + clampedCurrentSegments)
}

private func labelSegmentsBySlicing(
    interval: DateInterval,
    baseSegments: [TimelineLabelSegment],
    overrideSegments: [TimelineLabelSegment],
    preferOverride: Bool
) -> [TimelineLabelSegment] {
    let boundaries = Set(
        [interval.start, interval.end]
        + baseSegments.flatMap { [max(interval.start, $0.startDate), min(interval.end, $0.endDate)] }
        + overrideSegments.flatMap { [max(interval.start, $0.startDate), min(interval.end, $0.endDate)] }
    )
    .filter { $0 >= interval.start && $0 <= interval.end }
    .sorted()

    guard boundaries.count > 1 else { return [] }

    var slicedSegments: [TimelineLabelSegment] = []
    for index in boundaries.indices.dropLast() {
        let startDate = boundaries[index]
        let endDate = boundaries[index + 1]
        guard endDate > startDate else { continue }

        let midpoint = startDate.addingTimeInterval(endDate.timeIntervalSince(startDate) / 2)
        let baseSegment = baseSegments.first { $0.startDate <= midpoint && midpoint < $0.endDate }
        let overrideSegment = overrideSegments.first { $0.startDate <= midpoint && midpoint < $0.endDate }

        if preferOverride {
            let resolvedSegment = overrideSegment ?? baseSegment
            guard let resolvedSegment else { continue }
            appendLabelSegment(
                TimelineLabelSegment(
                    id: resolvedSegment.id,
                    label: resolvedSegment.label,
                    startDate: startDate,
                    endDate: endDate
                ),
                to: &slicedSegments
            )
        } else {
            guard let overrideSegment else { continue }
            guard let baseSegment, overrideSegment.label != baseSegment.label else { continue }
            appendLabelSegment(
                TimelineLabelSegment(
                    id: overrideSegment.id,
                    label: overrideSegment.label,
                    startDate: startDate,
                    endDate: endDate
                ),
                to: &slicedSegments
            )
        }
    }

    return slicedSegments
}

private func clippedLabelSegment(_ segment: TimelineLabelSegment, to interval: DateInterval) -> TimelineLabelSegment? {
    guard segment.endDate > segment.startDate else { return nil }
    let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
    guard interval.intersects(segmentInterval) else { return nil }
    let startDate = max(segment.startDate, interval.start)
    let endDate = min(segment.endDate, interval.end)
    guard endDate > startDate else { return nil }
    return TimelineLabelSegment(id: segment.id, label: segment.label, startDate: startDate, endDate: endDate)
}

private func labelSegments(of segment: TimelineLabelSegment, outside interval: DateInterval) -> [TimelineLabelSegment] {
    guard segment.endDate > segment.startDate else { return [] }
    let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
    guard interval.intersects(segmentInterval) else { return [segment] }

    var segments: [TimelineLabelSegment] = []
    if interval.start > segment.startDate {
        segments.append(TimelineLabelSegment(
            id: segment.id,
            label: segment.label,
            startDate: segment.startDate,
            endDate: min(interval.start, segment.endDate)
        ))
    }
    if interval.end < segment.endDate {
        segments.append(TimelineLabelSegment(
            id: segments.isEmpty ? segment.id : UUID(),
            label: segment.label,
            startDate: max(interval.end, segment.startDate),
            endDate: segment.endDate
        ))
    }

    return segments.filter { $0.endDate > $0.startDate }
}

func labelSegmentsByResizingBoundary(
    _ baselineSegments: [TimelineLabelSegment],
    changedSegment: TimelineLabelSegment,
    edge: TimelineLabelResizeEdge,
    in interval: DateInterval
) -> [TimelineLabelSegment] {
    let sourceSegments = normalizedLabelCoverage(baselineSegments, in: interval)
    guard let changedIndex = sourceSegments.firstIndex(where: { $0.id == changedSegment.id }) else {
        return sourceSegments
    }

    let originalSegment = sourceSegments[changedIndex]
    let clampedChangedSegment = TimelineLabelSegment(
        id: changedSegment.id,
        label: changedSegment.label,
        startDate: max(interval.start, min(changedSegment.startDate, interval.end)),
        endDate: max(interval.start, min(changedSegment.endDate, interval.end))
    )
    guard clampedChangedSegment.endDate > clampedChangedSegment.startDate else {
        return sourceSegments
    }

    var rebuiltSegments: [TimelineLabelSegment] = []
    for (index, segment) in sourceSegments.enumerated() where segment.id != changedSegment.id {
        if edge == .leading,
           index == changedIndex - 1,
           abs(segment.endDate.timeIntervalSince(originalSegment.startDate)) < 0.5 {
            appendLabelSegment(
                TimelineLabelSegment(
                    id: segment.id,
                    label: segment.label,
                    startDate: segment.startDate,
                    endDate: clampedChangedSegment.startDate
                ),
                to: &rebuiltSegments
            )
            continue
        }

        if edge == .trailing,
           index == changedIndex + 1,
           abs(segment.startDate.timeIntervalSince(originalSegment.endDate)) < 0.5 {
            appendLabelSegment(
                TimelineLabelSegment(
                    id: segment.id,
                    label: segment.label,
                    startDate: clampedChangedSegment.endDate,
                    endDate: segment.endDate
                ),
                to: &rebuiltSegments
            )
            continue
        }

        if segment.endDate <= clampedChangedSegment.startDate || segment.startDate >= clampedChangedSegment.endDate {
            appendLabelSegment(segment, to: &rebuiltSegments)
        } else {
            appendLabelSegment(
                TimelineLabelSegment(
                    id: segment.id,
                    label: segment.label,
                    startDate: segment.startDate,
                    endDate: min(segment.endDate, clampedChangedSegment.startDate)
                ),
                to: &rebuiltSegments
            )
            appendLabelSegment(
                TimelineLabelSegment(
                    label: segment.label,
                    startDate: max(segment.startDate, clampedChangedSegment.endDate),
                    endDate: segment.endDate
                ),
                to: &rebuiltSegments
            )
        }
    }

    appendLabelSegment(clampedChangedSegment, to: &rebuiltSegments)
    return normalizedLabelCoverage(rebuiltSegments, in: interval)
}

private struct TimelineEventContextOverlay: View {
    let segments: [ActivitySegment]
    let interval: DateInterval?
    let metrics: TimelineMetrics
    let streamCount: Int

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(segment.category.tint.opacity(0.13))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(segment.category.tint.opacity(0.20), lineWidth: 1)
                        )
                        .frame(width: eventWidth(segment, totalWidth: proxy.size.width), height: streamHeight)
                        .offset(x: eventOffset(segment, totalWidth: proxy.size.width), y: streamTopOffset)
                }
            }
        }
    }

    private var streamTopOffset: CGFloat {
        28 + metrics.laneSpacing
    }

    private var streamHeight: CGFloat {
        let laneCount = max(1, streamCount)
        return CGFloat(laneCount) * metrics.laneHeight
            + CGFloat(max(0, laneCount - 1)) * metrics.laneSpacing
    }

    private func eventOffset(_ segment: ActivitySegment, totalWidth: CGFloat) -> CGFloat {
        guard let interval, interval.duration > 0 else { return 0 }
        let startDate = min(max(segment.startDate, interval.start), interval.end)
        let elapsed = startDate.timeIntervalSince(interval.start)
        return totalWidth * elapsed / interval.duration
    }

    private func eventWidth(_ segment: ActivitySegment, totalWidth: CGFloat) -> CGFloat {
        guard let interval, interval.duration > 0 else { return 0 }
        let startDate = min(max(segment.startDate, interval.start), interval.end)
        let endDate = min(max(segment.endDate, interval.start), interval.end)
        let elapsed = startDate.timeIntervalSince(interval.start)
        let offset = totalWidth * elapsed / interval.duration
        let raw = totalWidth * max(0, endDate.timeIntervalSince(startDate)) / interval.duration
        return min(max(10, raw), max(0, totalWidth - offset))
    }
}

private struct ManualEventsListView: View {
    let events: [ManualActivityEvent]
    let onEdit: (ManualActivityEvent) -> Void
    let onDelete: (ManualActivityEvent) -> Void

    private var sortedEvents: [ManualActivityEvent] {
        events.sorted {
            if $0.startDate == $1.startDate {
                return $0.endDate < $1.endDate
            }

            return $0.startDate < $1.startDate
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manual Events")
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            if sortedEvents.isEmpty {
                Text("No events added for today.")
                    .productivityFont(.body)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(sortedEvents) { event in
                            ManualEventRow(event: event, onEdit: onEdit, onDelete: onDelete)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct ManualEventRow: View {
    let event: ManualActivityEvent
    let onEdit: (ManualActivityEvent) -> Void
    let onDelete: (ManualActivityEvent) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(event.label.tint)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)

                Text(detail)
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                onEdit(event)
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit event")

            Button(role: .destructive) {
                onDelete(event)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete event")
        }
        .padding(10)
        .background(ProductivityTheme.subtleBackground.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.28), lineWidth: 1)
        )
    }

    private var detail: String {
        let start = TimelineFormatters.time.string(from: event.startDate)
        let end = TimelineFormatters.time.string(from: event.endDate)
        return "\(start)-\(end) · \(event.label.title) · \(event.recurrence.title) · Alert: \(event.alert.title)"
    }
}

private enum ManualActivityPreset: String, CaseIterable, Identifiable {
    case custom
    case sleep
    case focusBlock
    case breakTime
    case meal
    case workout
    case commute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom: "Custom"
        case .sleep: "Sleep"
        case .focusBlock: "Focus Block"
        case .breakTime: "Break"
        case .meal: "Meal"
        case .workout: "Workout"
        case .commute: "Commute"
        }
    }
}

private struct ManualActivityEventForm: View {
    let eventID: UUID
    let dayInterval: DateInterval
    let isEditing: Bool
    let onSave: (ManualActivityEvent) -> Void
    let onCancel: () -> Void

    @State private var title: String
    @State private var preset: ManualActivityPreset
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var label: ActivityLabel
    @State private var isSleep: Bool
    @State private var recurrence: ManualActivityRecurrence
    @State private var alert: ManualActivityAlert
    @State private var weekdayMask: Set<Int>

    init(
        event: ManualActivityEvent? = nil,
        dayInterval: DateInterval,
        onSave: @escaping (ManualActivityEvent) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let defaultStart = max(Date(), dayInterval.start)
        let defaultEnd = min(dayInterval.end, defaultStart.addingTimeInterval(30 * 60))
        self.eventID = event?.id ?? UUID()
        self.dayInterval = dayInterval
        self.isEditing = event != nil
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: event?.title ?? "")
        _preset = State(initialValue: .custom)
        _startDate = State(initialValue: event?.startDate ?? defaultStart)
        _endDate = State(initialValue: event?.endDate ?? defaultEnd)
        _label = State(initialValue: event?.label ?? .productive)
        _isSleep = State(initialValue: event?.isSleep ?? false)
        _recurrence = State(initialValue: event?.recurrence ?? .none)
        _alert = State(initialValue: event?.alert ?? .none)
        _weekdayMask = State(initialValue: event?.weekdayMask ?? [Calendar.current.component(.weekday, from: event?.startDate ?? defaultStart)])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isEditing ? "Edit Event" : "Add Event")
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            Picker("Preset", selection: $preset) {
                ForEach(ManualActivityPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.menu)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    labelPicker
                    alertPicker
                }

                VStack(alignment: .leading, spacing: 10) {
                    labelPicker
                    alertPicker
                }
            }

            Toggle("Treat as sleep", isOn: $isSleep)
                .toggleStyle(.switch)

            Picker("Repeat", selection: $recurrence) {
                ForEach(ManualActivityRecurrence.allCases) { recurrence in
                    Text(recurrence.title).tag(recurrence)
                }
            }
            .pickerStyle(.segmented)

            if recurrence == .customWeekly {
                ManualEventWeekdayPicker(weekdayMask: $weekdayMask)
            }

            VStack(alignment: .leading, spacing: 6) {
                ManualEventTimePickerRow(title: "Starts", date: $startDate, dayInterval: dayInterval)
                ManualEventTimePickerRow(title: "Ends", date: $endDate, dayInterval: dayInterval)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    durationButtons
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], alignment: .leading, spacing: 8) {
                    durationButtons
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button(isEditing ? "Save" : "Add") {
                    onSave(event)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedTitle.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 520)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
        .onChange(of: startDate) { _, newStartDate in
            endDate = normalizedManualActivityEndDateAfterStartChange(
                startDate: newStartDate,
                endDate: endDate,
                dayInterval: dayInterval,
                allowsOvernight: isSleep
            )
        }
        .onChange(of: endDate) { _, newEndDate in
            endDate = normalizedManualActivityEndDateAfterEndChange(
                startDate: startDate,
                endDate: newEndDate,
                dayInterval: dayInterval,
                allowsOvernight: isSleep
            )
        }
        .onChange(of: isSleep) { _, newIsSleep in
            if !newIsSleep {
                endDate = normalizedManualActivityEndDateAfterEndChange(
                    startDate: startDate,
                    endDate: endDate,
                    dayInterval: dayInterval,
                    allowsOvernight: false
                )
            }
        }
        .onChange(of: preset) { _, newPreset in
            applyPreset(newPreset)
        }
    }

    private var event: ManualActivityEvent {
        normalizedManualActivityEventInput(
            id: eventID,
            title: trimmedTitle,
            startDate: startDate,
            endDate: endDate,
            label: label,
            isSleep: isSleep,
            recurrence: recurrence,
            alert: alert,
            weekdayMask: normalizedWeekdayMask,
            dayInterval: dayInterval
        )
    }

    private var labelPicker: some View {
        Picker("Label", selection: $label) {
            ForEach(ActivityLabel.allCases) { label in
                Text(label.title).tag(label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alertPicker: some View {
        Picker("Alert", selection: $alert) {
            ForEach(ManualActivityAlert.allCases) { alert in
                Text(alert.title).tag(alert)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationButtons: some View {
        Group {
            ManualEventDurationButton(title: "15m", seconds: 15 * 60, startDate: startDate, dayEnd: dayInterval.end, endDate: $endDate)
            ManualEventDurationButton(title: "30m", seconds: 30 * 60, startDate: startDate, dayEnd: dayInterval.end, endDate: $endDate)
            ManualEventDurationButton(title: "1h", seconds: 60 * 60, startDate: startDate, dayEnd: dayInterval.end, endDate: $endDate)
            ManualEventDurationButton(title: "2h", seconds: 2 * 60 * 60, startDate: startDate, dayEnd: dayInterval.end, endDate: $endDate)
            Button("All day") {
                startDate = dayInterval.start
                endDate = dayInterval.end
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var normalizedWeekdayMask: Set<Int> {
        weekdayMask.isEmpty ? [Calendar.current.component(.weekday, from: startDate)] : weekdayMask
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyPreset(_ preset: ManualActivityPreset) {
        guard preset != .custom else { return }
        let calendar = Calendar.current

        title = preset.title
        switch preset {
        case .custom:
            break
        case .sleep:
            label = .sleep
            isSleep = true
            recurrence = .daily
            alert = .none
            startDate = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: dayInterval.start)
                ?? dayInterval.start.addingTimeInterval(23 * 60 * 60)
            endDate = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: dayInterval.start)
                ?? dayInterval.start.addingTimeInterval(7 * 60 * 60)
        case .focusBlock:
            label = .productive
            isSleep = false
            recurrence = .none
            startDate = max(Date(), dayInterval.start)
            endDate = min(dayInterval.end, startDate.addingTimeInterval(90 * 60))
        case .breakTime:
            label = .unproductive
            isSleep = false
            recurrence = .none
            startDate = max(Date(), dayInterval.start)
            endDate = min(dayInterval.end, startDate.addingTimeInterval(15 * 60))
        case .meal:
            label = .unknown
            isSleep = false
            recurrence = .none
            startDate = max(Date(), dayInterval.start)
            endDate = min(dayInterval.end, startDate.addingTimeInterval(45 * 60))
        case .workout:
            label = .productive
            recurrence = .none
            startDate = max(Date(), dayInterval.start)
            endDate = min(dayInterval.end, startDate.addingTimeInterval(60 * 60))
        case .commute:
            label = .unknown
            recurrence = .none
            startDate = max(Date(), dayInterval.start)
            endDate = min(dayInterval.end, startDate.addingTimeInterval(30 * 60))
        }
    }
}

private struct ManualEventWeekdayPicker: View {
    @Binding var weekdayMask: Set<Int>

    private let symbols = Calendar.current.veryShortWeekdaySymbols

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...7, id: \.self) { weekday in
                Button {
                    toggle(weekday)
                } label: {
                    Text(symbols[symbols.index(symbols.startIndex, offsetBy: weekday - 1)])
                        .productivityFont(.captionStrong)
                        .frame(width: 28, height: 24)
                        .background(background(for: weekday), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(weekdayMask.contains(weekday) ? .white : ProductivityTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Repeat on \(Calendar.current.weekdaySymbols[weekday - 1])")
            }
        }
        .padding(6)
        .background(ProductivityTheme.subtleBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }

    private func background(for weekday: Int) -> Color {
        weekdayMask.contains(weekday) ? ProductivityTheme.accent.opacity(0.9) : ProductivityTheme.elevatedBackground.opacity(0.72)
    }

    private func toggle(_ weekday: Int) {
        if weekdayMask.contains(weekday) {
            weekdayMask.remove(weekday)
        } else {
            weekdayMask.insert(weekday)
        }
    }
}

func normalizedManualActivityEventInput(
    id: UUID,
    title: String,
    startDate: Date,
    endDate: Date,
    label: ActivityLabel,
    isSleep: Bool,
    recurrence: ManualActivityRecurrence,
    alert: ManualActivityAlert,
    weekdayMask: Set<Int>,
    dayInterval: DateInterval
) -> ManualActivityEvent {
    let normalizedStart = max(dayInterval.start, min(startDate, dayInterval.end.addingTimeInterval(-60)))
    let normalizedEnd: Date
    if endDate > startDate {
        normalizedEnd = max(normalizedStart.addingTimeInterval(60), min(dayInterval.end, endDate))
    } else {
        normalizedEnd = endDate
    }

    return ManualActivityEvent(
        id: id,
        title: title,
        startDate: normalizedStart,
        endDate: normalizedEnd,
        label: label,
        isSleep: isSleep,
        recurrence: recurrence,
        alert: alert,
        weekdayMask: recurrence == .customWeekly ? weekdayMask : []
    )
}

func normalizedManualActivityEndDateAfterStartChange(
    startDate: Date,
    endDate: Date,
    dayInterval: DateInterval,
    allowsOvernight: Bool
) -> Date {
    if allowsOvernight || endDate > startDate {
        return endDate
    }

    return min(dayInterval.end, startDate.addingTimeInterval(30 * 60))
}

func normalizedManualActivityEndDateAfterEndChange(
    startDate: Date,
    endDate: Date,
    dayInterval: DateInterval,
    allowsOvernight: Bool
) -> Date {
    if allowsOvernight || endDate > startDate {
        return endDate
    }

    return min(dayInterval.end, startDate.addingTimeInterval(30 * 60))
}

private struct ManualEventDurationButton: View {
    let title: String
    let seconds: TimeInterval
    let startDate: Date
    let dayEnd: Date
    @Binding var endDate: Date

    var body: some View {
        Button(title) {
            endDate = min(dayEnd, startDate.addingTimeInterval(seconds))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct ManualEventTimePickerRow: View {
    let title: String
    @Binding var date: Date
    let dayInterval: DateInterval

    @FocusState private var isTextFieldFocused: Bool
    @State private var draftText = ""

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .productivityFont(.bodyMedium)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .frame(width: 52, alignment: .leading)

            HStack(spacing: 3) {
                TextField("", text: $draftText)
                    .textFieldStyle(.plain)
                    .productivityFont(.captionMonospaced)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .frame(width: 38, height: 22, alignment: .center)
                    .onSubmit(commitDraftText)

                VStack(spacing: 0) {
                    timeStepButton(systemName: "chevron.up", delta: 5 * 60)
                    timeStepButton(systemName: "chevron.down", delta: -5 * 60)
                }
                .frame(width: 14, height: 22)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(ProductivityTheme.subtleBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
            )
            .fixedSize()
        }
        .frame(height: 28, alignment: .center)
        .onAppear(perform: syncDraftText)
        .onChange(of: date) { _, _ in
            guard !isTextFieldFocused else { return }
            syncDraftText()
        }
        .onChange(of: isTextFieldFocused) { _, isFocused in
            if isFocused {
                syncDraftText()
            } else {
                commitDraftText()
            }
        }
    }

    private func timeStepButton(systemName: String, delta: TimeInterval) -> some View {
        Button {
            date = clamped(date.addingTimeInterval(delta))
            syncDraftText()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(ProductivityTheme.textSecondary)
                .frame(width: 14, height: 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func syncDraftText() {
        draftText = TimelineFormatters.time.string(from: date)
    }

    private func commitDraftText() {
        guard let parsedDate = parsedDraftDate else {
            syncDraftText()
            return
        }

        date = clamped(parsedDate)
        syncDraftText()
    }

    private var parsedDraftDate: Date? {
        let parts = draftText.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let hour = parts[0]
        let minute = parts[1]
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }

        return Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: dayInterval.start
        )
    }

    private func clamped(_ proposedDate: Date) -> Date {
        min(dayInterval.end, max(dayInterval.start, proposedDate))
    }
}

private struct TimelineDayProgressView: View {
    let dayInterval: DateInterval
    let segments: [ActivitySegment]
    let hidesSleep: Bool

    @State private var hoveredItem: DayProgressHoverItem?

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
            let metrics = renderMetrics
            let progress = dayProgress(at: context.date, metrics: metrics)
            let remainingText = DurationFormatting.abbreviated(remainingSeconds(
                at: context.date,
                metrics: metrics
            ))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Label(
                        title(for: metrics),
                        systemImage: metrics.isWakingMode ? "sun.max" : "clock"
                    )
                        .productivityFont(.sectionLabel)
                        .foregroundStyle(ProductivityTheme.textPrimary)

                    Spacer(minLength: 8)

                    Text("\(Int(progress * 100))% elapsed")
                        .productivityFont(.noteMonospaced)
                        .foregroundStyle(ProductivityTheme.textSecondary)

                    Text("\(remainingText) left")
                        .productivityFont(.noteMonospaced)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                GeometryReader { proxy in
                    let renderedDisplaySegments = displaySegments(metrics: metrics)
                    let renderedSleepBoundaryMarkers = sleepEventBoundaryMarkers(metrics: metrics)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(ProductivityTheme.subtleBackground.opacity(0.7))

                        ForEach(renderedDisplaySegments) { displaySegment in
                            let width = eventWidth(
                                displaySegment,
                                totalWidth: proxy.size.width,
                                metrics: metrics
                            )
                            RoundedRectangle(cornerRadius: 4)
                                .fill(displaySegment.segment.category.tint.opacity(0.22))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(
                                            displaySegment.segment.category.tint.opacity(0.98),
                                            lineWidth: 1.8
                                        )
                                )
                                .frame(width: width, height: 18)
                                .position(
                                    x: eventOrigin(
                                        displaySegment,
                                        totalWidth: proxy.size.width,
                                        eventWidth: width,
                                        metrics: metrics
                                    ) + (width / 2),
                                    y: proxy.size.height / 2
                                )
                                .allowsHitTesting(false)
                        }

                        ForEach(renderedSleepBoundaryMarkers) { marker in
                            SleepBoundaryMarkerView()
                                .position(
                                    x: sleepBoundaryOffset(
                                        marker,
                                        totalWidth: proxy.size.width,
                                        metrics: metrics
                                    ) + (SleepBoundaryMarkerView.width / 2),
                                    y: proxy.size.height / 2
                                )
                                .allowsHitTesting(false)
                                .zIndex(3)
                        }

                        if let hoveredItem {
                            Text(hoveredItem.helpText)
                                .productivityFont(.noteStrong)
                                .foregroundStyle(ProductivityTheme.textPrimary)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .frame(width: hoverLabelWidth(for: hoveredItem), alignment: hoverAlignment(for: hoveredItem))
                                .background(ProductivityTheme.elevatedBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(hoveredItem.category.tint.opacity(0.65), lineWidth: 1)
                                )
                                .offset(
                                    x: hoverLabelOffset(
                                        hoveredItem,
                                        totalWidth: proxy.size.width,
                                        metrics: metrics
                                    ),
                                    y: -30
                                )
                                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                                .allowsHitTesting(false)
                                .zIndex(4)
                        }

                        RoundedRectangle(cornerRadius: 5)
                            .fill(ProductivityTheme.accent.opacity(0.82))
                            .frame(width: max(8, proxy.size.width * progress), height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .allowsHitTesting(false)

                        Rectangle()
                            .fill(ProductivityTheme.textPrimary.opacity(0.72))
                            .frame(width: 1.5)
                            .offset(x: max(0, min(proxy.size.width - 1.5, proxy.size.width * progress)))
                            .allowsHitTesting(false)
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredItem = hoverItem(
                                at: location,
                                displaySegments: renderedDisplaySegments,
                                sleepBoundaryMarkers: renderedSleepBoundaryMarkers,
                                totalWidth: proxy.size.width,
                                totalHeight: proxy.size.height,
                                metrics: metrics
                            )
                        case .ended:
                            hoveredItem = nil
                        }
                    }
                }
                .frame(height: 22)
            }
            .padding(12)
            .background(ProductivityTheme.subtleBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.36), lineWidth: 1)
            )
        }
        .onChange(of: hidesSleep) { _, _ in
            clearHoverState()
        }
        .onChange(of: hoverSourceSignature) { _, _ in
            clearHoverState()
        }
    }

    private func clearHoverState() {
        hoveredItem = nil
    }

    private func dayProgress(at date: Date, metrics: DayProgressRenderMetrics) -> Double {
        guard metrics.visibleDayDuration > 0 else { return 0 }
        return min(1, max(0, visibleElapsedSeconds(until: date, metrics: metrics) / metrics.visibleDayDuration))
    }

    private func remainingSeconds(at date: Date, metrics: DayProgressRenderMetrics) -> TimeInterval {
        max(0, metrics.visibleDayDuration - visibleElapsedSeconds(until: date, metrics: metrics))
    }

    private func eventOffset(
        _ displaySegment: DayProgressDisplaySegment,
        totalWidth: CGFloat,
        metrics: DayProgressRenderMetrics
    ) -> CGFloat {
        guard metrics.visibleDayDuration > 0 else { return 0 }
        return totalWidth * visibleElapsedSeconds(until: displaySegment.interval.start, metrics: metrics) / metrics.visibleDayDuration
    }

    private func eventOrigin(
        _ displaySegment: DayProgressDisplaySegment,
        totalWidth: CGFloat,
        eventWidth: CGFloat? = nil,
        metrics: DayProgressRenderMetrics
    ) -> CGFloat {
        let width = eventWidth ?? self.eventWidth(
            displaySegment,
            totalWidth: totalWidth,
            metrics: metrics
        )
        return min(max(0, eventOffset(
            displaySegment,
            totalWidth: totalWidth,
            metrics: metrics
        )), max(0, totalWidth - width))
    }

    private func eventWidth(
        _ displaySegment: DayProgressDisplaySegment,
        totalWidth: CGFloat,
        metrics: DayProgressRenderMetrics
    ) -> CGFloat {
        guard metrics.visibleDayDuration > 0 else { return 0 }
        return max(
            8,
            totalWidth * displaySegment.interval.duration / metrics.visibleDayDuration
        )
    }

    private func eventTitle(_ segment: ActivitySegment) -> String {
        segment.appName
    }

    private func eventTimeRange(_ segment: ActivitySegment) -> String {
        "\(TimelineFormatters.time.string(from: segment.startDate))-\(TimelineFormatters.time.string(from: segment.endDate))"
    }

    private func eventHelp(_ segment: ActivitySegment) -> String {
        "\(eventTitle(segment)): \(eventTimeRange(segment)) · \(segment.category.title)"
    }

    private func sleepBoundaryOffset(
        _ marker: SleepBoundaryMarker,
        totalWidth: CGFloat,
        metrics: DayProgressRenderMetrics
    ) -> CGFloat {
        let markerWidth = SleepBoundaryMarkerView.width
        let edgeInset = SleepBoundaryMarkerView.edgeInset
        let position = totalWidth * dayProgress(at: marker.date, metrics: metrics)
        switch marker.edge {
        case .leading:
            return min(edgeInset, max(0, totalWidth - markerWidth))
        case .center:
            return min(max(0, position - markerWidth / 2), max(0, totalWidth - markerWidth))
        case .trailing:
            return max(0, totalWidth - markerWidth - edgeInset)
        }
    }

    private func hoverLabelOffset(
        _ item: DayProgressHoverItem,
        totalWidth: CGFloat,
        metrics: DayProgressRenderMetrics
    ) -> CGFloat {
        switch item {
        case .segment(let displaySegment):
            let labelWidth = hoverLabelWidth(for: item)
            let width = eventWidth(
                displaySegment,
                totalWidth: totalWidth,
                metrics: metrics
            )
            let centered = eventOrigin(
                displaySegment,
                totalWidth: totalWidth,
                eventWidth: width,
                metrics: metrics
            ) + (width / 2) - (labelWidth / 2)
            return min(max(0, centered), max(0, totalWidth - labelWidth))
        case .sleepMarker(let marker):
            switch marker.edge {
            case .leading:
                return 0
            case .center:
                let labelWidth = hoverLabelWidth(for: item)
                let centered = sleepBoundaryOffset(
                    marker,
                    totalWidth: totalWidth,
                    metrics: metrics
                ) + (SleepBoundaryMarkerView.width / 2) - (labelWidth / 2)
                return min(max(0, centered), max(0, totalWidth - labelWidth))
            case .trailing:
                return max(0, totalWidth - hoverLabelWidth(for: item))
            }
        }
    }

    private func hoverLabelWidth(for item: DayProgressHoverItem) -> CGFloat {
        switch item {
        case .segment:
            return 220
        case .sleepMarker:
            return 150
        }
    }

    private func hoverAlignment(for item: DayProgressHoverItem) -> Alignment {
        switch item {
        case .segment:
            return .center
        case .sleepMarker(let marker):
            switch marker.edge {
            case .leading:
                return .leading
            case .center:
                return .center
            case .trailing:
                return .trailing
            }
        }
    }

    private func hoverItem(
        at location: CGPoint,
        displaySegments: [DayProgressDisplaySegment],
        sleepBoundaryMarkers: [SleepBoundaryMarker],
        totalWidth: CGFloat,
        totalHeight: CGFloat,
        metrics: DayProgressRenderMetrics
    ) -> DayProgressHoverItem? {
        let markerHitPadding: CGFloat = 4
        for marker in sleepBoundaryMarkers.reversed() {
            let markerRect = CGRect(
                x: sleepBoundaryOffset(
                    marker,
                    totalWidth: totalWidth,
                    metrics: metrics
                ),
                y: (totalHeight - 18) / 2,
                width: SleepBoundaryMarkerView.width,
                height: 18
            ).insetBy(dx: -markerHitPadding, dy: -markerHitPadding)

            if markerRect.contains(location) {
                return .sleepMarker(marker)
            }
        }

        let segmentHitPadding: CGFloat = 2
        for displaySegment in displaySegments.reversed() {
            let width = eventWidth(
                displaySegment,
                totalWidth: totalWidth,
                metrics: metrics
            )
            let segmentRect = CGRect(
                x: eventOrigin(
                    displaySegment,
                    totalWidth: totalWidth,
                    eventWidth: width,
                    metrics: metrics
                ),
                y: (totalHeight - 18) / 2,
                width: width,
                height: 18
            ).insetBy(dx: -segmentHitPadding, dy: -segmentHitPadding)

            if segmentRect.contains(location) {
                return .segment(displaySegment)
            }
        }

        return nil
    }

    private var hoverSourceSignature: Int {
        var hasher = Hasher()
        for segment in segments { hasher.combine(segment) }
        return hasher.finalize()
    }

    private func displaySegments(metrics: DayProgressRenderMetrics) -> [DayProgressDisplaySegment] {
        visibleSegments.flatMap { segment in
            visibleIntervals(for: segment, metrics: metrics).map { interval in
                DayProgressDisplaySegment(segment: segment, interval: interval)
            }
        }
    }

    private func visibleIntervals(for segment: ActivitySegment, metrics: DayProgressRenderMetrics) -> [DateInterval] {
        guard let segmentInterval = clippedInterval(segment.safeInterval, to: dayInterval) else { return [] }
        guard metrics.isWakingMode else { return [segmentInterval] }
        return subtract(metrics.hiddenSleepIntervals, from: segmentInterval)
    }

    private func subtract(_ excludedIntervals: [DateInterval], from interval: DateInterval) -> [DateInterval] {
        var remainingIntervals = [interval]

        for excludedInterval in excludedIntervals {
            remainingIntervals = remainingIntervals.flatMap { subtract(excludedInterval, from: $0) }
            guard !remainingIntervals.isEmpty else { break }
        }

        return remainingIntervals
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

    private func title(for metrics: DayProgressRenderMetrics) -> String {
        metrics.isWakingMode ? "Waking Progress" : "Day Progress"
    }

    private var visibleSegments: [ActivitySegment] {
        segments.filter(\.isDayProgressDisplayEvent)
    }

    private var renderMetrics: DayProgressRenderMetrics {
        let hiddenSleepIntervals = wakingModeHiddenSleepIntervals
        return DayProgressRenderMetrics(
            hiddenSleepIntervals: hiddenSleepIntervals,
            visibleDayDuration: visibleDayDuration(excluding: hiddenSleepIntervals)
        )
    }

    private var wakingModeHiddenSleepIntervals: [DateInterval] {
        guard hidesSleep else { return [] }
        return mergedIntervals(
            segments
                .filter(isHiddenSleepEvent)
                .compactMap { clippedInterval($0.safeInterval, to: dayInterval) }
        )
    }

    private func sleepEventBoundaryMarkers(
        metrics: DayProgressRenderMetrics
    ) -> [SleepBoundaryMarker] {
        let markers = sleepEventIntervals.flatMap { interval in
            var markers: [SleepBoundaryMarker] = []

            if interval.start > dayInterval.start {
                markers.append(SleepBoundaryMarker(
                    date: interval.start,
                    edge: interval.end >= dayInterval.end ? .trailing : .center,
                    kind: .sleepStarted
                ))
            }

            if interval.end < dayInterval.end {
                markers.append(SleepBoundaryMarker(
                    date: interval.end,
                    edge: interval.start <= dayInterval.start ? .leading : .center,
                    kind: .wokeUp
                ))
            }

            return markers
        }

        return deduplicatedSleepBoundaryMarkers(
            markers,
            metrics: metrics
        )
    }

    private var sleepEventIntervals: [DateInterval] {
        mergedIntervals(
            segments
                .filter(\.isManualSleepEvent)
                .compactMap { clippedInterval($0.safeInterval, to: dayInterval) }
        )
    }

    private func deduplicatedSleepBoundaryMarkers(
        _ markers: [SleepBoundaryMarker],
        metrics: DayProgressRenderMetrics
    ) -> [SleepBoundaryMarker] {
        var seenKeys = Set<String>()
        var deduplicatedMarkers: [SleepBoundaryMarker] = []

        for marker in markers {
            let positionBucket = Int((
                visibleElapsedSeconds(
                    until: marker.date,
                    metrics: metrics
                ) * 1000
            ).rounded())
            let key = "\(marker.edge)-\(positionBucket)-\(marker.kind)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            deduplicatedMarkers.append(marker)
        }

        return deduplicatedMarkers
    }

    private func visibleDayDuration(excluding hiddenSleepIntervals: [DateInterval]) -> TimeInterval {
        let hiddenDuration = hiddenSleepIntervals.reduce(0) { $0 + $1.duration }
        return max(60, dayInterval.duration - hiddenDuration)
    }

    private func visibleElapsedSeconds(until date: Date, metrics: DayProgressRenderMetrics) -> TimeInterval {
        let clampedDate = min(max(date, dayInterval.start), dayInterval.end)
        let elapsed = max(0, clampedDate.timeIntervalSince(dayInterval.start))
        let hiddenElapsed = metrics.hiddenSleepIntervals.reduce(0) { total, interval in
            guard clampedDate > interval.start else { return total }
            return total + max(0, min(clampedDate, interval.end).timeIntervalSince(interval.start))
        }

        return min(metrics.visibleDayDuration, max(0, elapsed - hiddenElapsed))
    }

    private func isHiddenSleepEvent(_ segment: ActivitySegment) -> Bool {
        segment.isDayProgressSleepBoundary
    }

    private func clippedInterval(_ interval: DateInterval?, to bounds: DateInterval) -> DateInterval? {
        guard let interval, interval.intersects(bounds) else { return nil }
        let start = max(interval.start, bounds.start)
        let end = min(interval.end, bounds.end)
        guard end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func mergedIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        let sortedIntervals = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = []

        for interval in sortedIntervals {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }

            if last.end >= interval.start {
                merged.removeLast()
                merged.append(DateInterval(start: last.start, end: max(last.end, interval.end)))
            } else {
                merged.append(interval)
            }
        }

        return merged
    }
}

private struct DayProgressRenderMetrics {
    let hiddenSleepIntervals: [DateInterval]
    let visibleDayDuration: TimeInterval

    var isWakingMode: Bool {
        !hiddenSleepIntervals.isEmpty
    }
}

private struct SleepBoundaryMarker: Identifiable, Hashable {
    enum Edge {
        case leading
        case center
        case trailing
    }

    enum Kind {
        case wokeUp
        case sleepStarted

        var title: String {
            switch self {
            case .wokeUp: "Woke up"
            case .sleepStarted: "Sleep starts"
            }
        }
    }

    let date: Date
    let edge: Edge
    let kind: Kind

    var id: String {
        "\(kind)-\(date.timeIntervalSinceReferenceDate)"
    }

    var helpText: String {
        "\(kind.title): \(TimelineFormatters.time.string(from: date))"
    }
}

private struct DayProgressDisplaySegment: Identifiable, Hashable {
    let segment: ActivitySegment
    let interval: DateInterval

    var id: String {
        "\(segment.id.uuidString)-\(interval.start.timeIntervalSinceReferenceDate)-\(interval.end.timeIntervalSinceReferenceDate)"
    }

    var helpText: String {
        let start = TimelineFormatters.time.string(from: interval.start)
        let end = TimelineFormatters.time.string(from: interval.end)
        return "\(segment.appName): \(start)-\(end) · \(segment.category.title)"
    }
}

private enum DayProgressHoverItem: Hashable {
    case segment(DayProgressDisplaySegment)
    case sleepMarker(SleepBoundaryMarker)

    var isSleepMarker: Bool {
        if case .sleepMarker = self {
            return true
        }

        return false
    }

    var helpText: String {
        switch self {
        case .segment(let displaySegment):
            return displaySegment.helpText
        case .sleepMarker(let marker):
            return marker.helpText
        }
    }

    var category: ActivityCategory {
        switch self {
        case .segment(let displaySegment):
            return displaySegment.segment.category
        case .sleepMarker:
            return .focus
        }
    }
}

private struct SleepBoundaryMarkerView: View {
    static let width: CGFloat = 10
    static let edgeInset: CGFloat = 2

    var body: some View {
        Capsule(style: .continuous)
            .fill(ActivityLabel.unknown.tint.opacity(0.28))
            .overlay(
                Capsule(style: .continuous)
                    .stroke(ActivityLabel.unknown.tint.opacity(0.96), lineWidth: 1.8)
            )
            .overlay {
                Circle()
                    .fill(ProductivityTheme.textPrimary.opacity(0.92))
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(width: Self.width, height: 18)
            .shadow(color: ProductivityTheme.background.opacity(0.28), radius: 2, y: 0.5)
    }
}

private struct TimelineLabelColumnView: View {
    let streams: [TimelineStream]
    let metrics: TimelineMetrics
    let showsLabelLane: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.laneSpacing) {
            Text("Streams")
                .productivityFont(.noteMedium)
                .foregroundStyle(ProductivityTheme.textSecondary.opacity(0.68))
                .frame(width: metrics.labelWidth, height: 28, alignment: .leading)

            ForEach(streams) { stream in
                Text("Stream \(stream.number)")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: metrics.labelWidth, height: metrics.laneHeight, alignment: .leading)
            }

            if showsLabelLane {
                Text("Labels")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .frame(width: metrics.labelWidth, height: metrics.laneHeight, alignment: .leading)
            }
        }
    }
}

private struct TimelineRulerTrackView: View {
    let interval: DateInterval?
    let metrics: TimelineMetrics

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(ticks, id: \.offset) { tick in
                    Rectangle()
                        .fill(ProductivityTheme.border.opacity(0.62))
                        .frame(width: 1, height: 12)
                        .offset(x: lineXPosition(tick, in: proxy.size.width))

                    Text(tick.label)
                        .productivityFont(.noteMonospaced)
                        .foregroundStyle(ProductivityTheme.textSecondary.opacity(0.68))
                        .frame(width: 44, alignment: textAlignment(for: tick))
                        .offset(x: labelXPosition(tick, in: proxy.size.width), y: 14)
                }
            }
        }
        .frame(height: 28)
    }

    private var ticks: [TimelineTick] {
        guard let interval, interval.duration > 0 else { return [] }
        return metrics.tickOffsets.map { offset in
            let date = interval.start.addingTimeInterval(interval.duration * offset)
            return TimelineTick(offset: offset, label: TimelineFormatters.time.string(from: date))
        }
    }

    private func lineXPosition(_ tick: TimelineTick, in width: CGFloat) -> CGFloat {
        min(max(0, width * tick.offset), max(0, width - 1))
    }

    private func labelXPosition(_ tick: TimelineTick, in width: CGFloat) -> CGFloat {
        let labelWidth: CGFloat = 44
        let centeredPosition = (width * tick.offset) - (labelWidth / 2)
        return min(max(0, centeredPosition), max(0, width - labelWidth))
    }

    private func textAlignment(for tick: TimelineTick) -> Alignment {
        if tick.offset == 0 { return .leading }
        if tick.offset == 1 { return .trailing }
        return .center
    }
}

private struct TimelineStreamTrackView: View {
    let stream: TimelineStream
    let interval: DateInterval?
    let metrics: TimelineMetrics

    @State private var hoveredSegment: ActivitySegment?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                TimelineTrackView(interval: interval, metrics: metrics) { trackWidth in
                    ForEach(stream.segments) { segment in
                        let layout = segmentLayout(segment, totalWidth: trackWidth)
                        TimelineClipView(segment: segment)
                            .frame(width: layout.width, height: metrics.clipHeight)
                            .offset(x: layout.offset)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }

                // Inline hover tooltip shown only for collapsed clips (< 34 px wide).
                // Displayed at lane level so it always stays within the clipped VStack.
                if let hovered = hoveredSegment, segmentLayout(hovered, totalWidth: width).width < 34 {
                    clipHoverLabel(for: hovered, totalWidth: width)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(10)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredSegment = findSegment(at: location, totalWidth: width)
                    }
                case .ended:
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredSegment = nil
                    }
                }
            }
        }
    }

    private func clipHoverLabel(for segment: ActivitySegment, totalWidth: CGFloat) -> some View {
        let layout = segmentLayout(segment, totalWidth: totalWidth)
        let tooltipWidth: CGFloat = 220
        let tooltipX = min(max(0, layout.offset + layout.width / 2 - tooltipWidth / 2), max(0, totalWidth - tooltipWidth))
        let title = segment.isLifecycleContext ? segment.title : segment.appName
        let start = TimelineFormatters.time.string(from: segment.startDate)
        let end = TimelineFormatters.time.string(from: segment.endDate)
        let label = "\(title) · \(start)–\(end) · \(DurationFormatting.abbreviated(segment.duration))"

        return Text(label)
            .productivityFont(.noteStrong)
            .foregroundStyle(ProductivityTheme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: tooltipWidth, alignment: .center)
            .background(ProductivityTheme.elevatedBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(segment.category.tint.opacity(0.65), lineWidth: 1)
            )
            .offset(x: tooltipX)
            .allowsHitTesting(false)
    }

    private func findSegment(at location: CGPoint, totalWidth: CGFloat) -> ActivitySegment? {
        for segment in stream.segments.reversed() {
            let layout = segmentLayout(segment, totalWidth: totalWidth)
            let rect = CGRect(
                x: layout.offset,
                y: (metrics.laneHeight - metrics.clipHeight) / 2,
                width: layout.width,
                height: metrics.clipHeight
            ).insetBy(dx: -3, dy: -3)
            if rect.contains(location) {
                return segment
            }
        }
        return nil
    }

    private func segmentLayout(_ segment: ActivitySegment, totalWidth: CGFloat) -> TimelineSegmentLayout {
        guard let interval, interval.duration > 0 else {
            return TimelineSegmentLayout(offset: 0, width: 0)
        }

        let startDate = min(max(segment.startDate, interval.start), interval.end)
        let endDate = min(max(segment.endDate, interval.start), interval.end)
        let elapsed = startDate.timeIntervalSince(interval.start)
        let offset = totalWidth * elapsed / interval.duration
        let raw = totalWidth * max(0, endDate.timeIntervalSince(startDate)) / interval.duration
        let width = min(max(12, raw), max(0, totalWidth - offset))
        return TimelineSegmentLayout(offset: offset, width: width)
    }
}

private struct TimelineSegmentLayout {
    let offset: CGFloat
    let width: CGFloat
}

private struct TimelineLabelTrackView: View {
    @Binding var labelSegments: [TimelineLabelSegment]
    @Binding var baselineSegments: [TimelineLabelSegment]
    let interval: DateInterval?
    let metrics: TimelineMetrics
    let isEditingEnabled: Bool
    let onCommit: ([TimelineLabelSegment]) -> Void

    var body: some View {
        TimelineTrackView(interval: interval, metrics: metrics) { width in
            ForEach($labelSegments) { $segment in
                TimelineLabelBlockView(
                    segment: $segment,
                    isEditingEnabled: isEditingEnabled,
                    resizeAction: { edge, baselineStart, baselineEnd, translation in
                        resizeSegment(
                            segmentID: segment.id,
                            edge: edge,
                            baselineStart: baselineStart,
                            baselineEnd: baselineEnd,
                            translation: translation,
                            totalWidth: width
                        )
                    },
                    resizeEndAction: {
                        finalizeResize(segmentID: segment.id)
                    },
                    labelChangeAction: { label in
                        changeLabel(segmentID: segment.id, to: label)
                    }
                )
                .frame(width: labelWidth(segment, totalWidth: width), height: metrics.clipHeight)
                .offset(x: labelOffset(segment, totalWidth: width))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }

    private func labelOffset(_ segment: TimelineLabelSegment, totalWidth: CGFloat) -> CGFloat {
        guard let interval, interval.duration > 0 else { return 0 }
        let startDate = max(segment.startDate, interval.start)
        let elapsed = startDate.timeIntervalSince(interval.start)
        return totalWidth * elapsed / interval.duration
    }

    private func labelWidth(_ segment: TimelineLabelSegment, totalWidth: CGFloat) -> CGFloat {
        guard let interval, interval.duration > 0 else { return 0 }
        let startDate = max(segment.startDate, interval.start)
        let endDate = min(segment.endDate, interval.end)
        let offset = labelOffset(segment, totalWidth: totalWidth)
        let raw = totalWidth * max(0, endDate.timeIntervalSince(startDate)) / interval.duration
        return min(max(12, raw), max(0, totalWidth - offset))
    }

    private func resizeSegment(
        segmentID: UUID,
        edge: TimelineLabelResizeEdge,
        baselineStart: Date,
        baselineEnd: Date,
        translation: CGFloat,
        totalWidth: CGFloat
    ) {
        guard let interval, interval.duration > 0, totalWidth > 0 else {
            return
        }

        let delta = interval.duration * TimeInterval(translation / totalWidth)
        let minimumDuration = max(30, interval.duration * 0.004)
        let sourceSegments = activeResizeBaseline()
        guard let sourceSegment = sourceSegments.first(where: { $0.id == segmentID }) else { return }

        let changedSegment: TimelineLabelSegment
        switch edge {
        case .leading:
            let proposedStart = baselineStart.addingTimeInterval(delta)
            changedSegment = TimelineLabelSegment(
                id: sourceSegment.id,
                label: sourceSegment.label,
                startDate: max(interval.start, min(baselineEnd.addingTimeInterval(-minimumDuration), proposedStart)),
                endDate: baselineEnd
            )
        case .trailing:
            let proposedEnd = baselineEnd.addingTimeInterval(delta)
            changedSegment = TimelineLabelSegment(
                id: sourceSegment.id,
                label: sourceSegment.label,
                startDate: baselineStart,
                endDate: min(interval.end, max(baselineStart.addingTimeInterval(minimumDuration), proposedEnd))
            )
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            labelSegments = labelSegmentsByResizingBoundary(
                sourceSegments,
                changedSegment: changedSegment,
                edge: edge,
                in: interval
            )
        }
    }

    private func finalizeResize(segmentID: UUID) {
        guard labelSegments.contains(where: { $0.id == segmentID }) else { return }
        mergeAdjacentLabels()
        normalizeLabelCoverage()
        baselineSegments = labelSegments
        onCommit(labelSegments)
    }

    private func changeLabel(segmentID: UUID, to label: ActivityLabel) {
        guard let index = labelSegments.firstIndex(where: { $0.id == segmentID }) else { return }
        labelSegments[index].label = label
        mergeAdjacentLabels()
        normalizeLabelCoverage()
        baselineSegments = labelSegments
        onCommit(labelSegments)
    }

    private func normalizeLabelCoverage() {
        guard let interval else { return }
        labelSegments = normalizedLabelCoverage(labelSegments, in: interval)
    }

    private func activeResizeBaseline() -> [TimelineLabelSegment] {
        if isEditingEnabled && !baselineSegments.isEmpty {
            baselineSegments
        } else {
            labelSegments
        }
    }

    private func rebuildLabelsFromBaseline(changedSegment: TimelineLabelSegment) {
        var rebuiltSegments: [TimelineLabelSegment] = []
        let sourceSegments = isEditingEnabled && !baselineSegments.isEmpty ? baselineSegments : labelSegments

        for segment in sourceSegments where segment.id != changedSegment.id {
            if segment.endDate <= changedSegment.startDate || segment.startDate >= changedSegment.endDate {
                rebuiltSegments.append(segment)
            } else {
                if segment.startDate < changedSegment.startDate {
                    rebuiltSegments.append(TimelineLabelSegment(
                        id: segment.id,
                        label: segment.label,
                        startDate: segment.startDate,
                        endDate: changedSegment.startDate
                    ))
                }

                if segment.endDate > changedSegment.endDate {
                    rebuiltSegments.append(TimelineLabelSegment(
                        label: segment.label,
                        startDate: changedSegment.endDate,
                        endDate: segment.endDate
                    ))
                }
            }
        }

        rebuiltSegments.append(changedSegment)
        labelSegments = rebuiltSegments
            .filter { $0.duration > 0 }
            .sorted { $0.startDate < $1.startDate }
    }

    private func mergeAdjacentLabels() {
        let sortedSegments = labelSegments.sorted { $0.startDate < $1.startDate }
        var mergedSegments: [TimelineLabelSegment] = []

        for segment in sortedSegments where segment.duration > 0 {
            if let lastSegment = mergedSegments.last,
               lastSegment.label == segment.label,
               abs(lastSegment.endDate.timeIntervalSince(segment.startDate)) < 0.5 {
                mergedSegments.removeLast()
                mergedSegments.append(TimelineLabelSegment(
                    id: lastSegment.id,
                    label: lastSegment.label,
                    startDate: lastSegment.startDate,
                    endDate: segment.endDate
                ))
            } else {
                mergedSegments.append(segment)
            }
        }

        labelSegments = mergedSegments
    }
}


private struct TimelineTrackView<Content: View>: View {
    let interval: DateInterval?
    let metrics: TimelineMetrics
    @ViewBuilder let content: (CGFloat) -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                TimelineGridView(tickOffsets: metrics.tickOffsets)

                RoundedRectangle(cornerRadius: 4)
                    .fill(emptyTrackFill)
                    .frame(height: metrics.clipHeight)

                if interval != nil {
                    content(proxy.size.width)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var emptyTrackFill: Color {
        if colorScheme == .light {
            return Color(red: 0.840, green: 0.865, blue: 0.895).opacity(0.68)
        }

        return ProductivityTheme.subtleBackground.opacity(0.54)
    }
}

private struct TimelineGridView: View {
    let tickOffsets: [Double]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ForEach(tickOffsets, id: \.self) { offset in
                    Rectangle()
                        .fill(ProductivityTheme.border.opacity(0.36))
                        .frame(width: 1)
                        .offset(x: min(max(0, proxy.size.width * offset), max(0, proxy.size.width - 1)))
                }
            }
        }
    }
}

private struct TimelineClipView: View {
    let segment: ActivitySegment

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(segment.category.tint.gradient)
                    .overlay(alignment: .leading) {
                        if proxy.size.width >= 34 {
                            Text(displayTitle)
                                .productivityFont(.noteMedium)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 7)
                                .minimumScaleFactor(0.75)
                                .frame(maxWidth: proxy.size.width, alignment: .leading)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: segment.category.tint.opacity(0.18), radius: 6, y: 3)
                    .help("\(displayTitle) · \(TimelineFormatters.time.string(from: segment.startDate))–\(TimelineFormatters.time.string(from: segment.endDate)) · \(DurationFormatting.abbreviated(segment.duration))")
                    .accessibilityLabel(displayTitle)
                    .accessibilityHint(segment.displayContext)

                if proxy.size.width < 34 {
                    Capsule()
                        .fill(.white.opacity(0.72))
                        .frame(width: 4, height: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var displayTitle: String {
        segment.isLifecycleContext ? segment.title : segment.appName
    }
}

enum TimelineLabelResizeEdge: Equatable {
    case leading
    case trailing
}

private struct TimelineLabelBlockView: View {
    @Binding var segment: TimelineLabelSegment
    let isEditingEnabled: Bool
    let resizeAction: (TimelineLabelResizeEdge, Date, Date, CGFloat) -> Void
    let resizeEndAction: () -> Void
    let labelChangeAction: (ActivityLabel) -> Void

    @State private var isLabelPickerPresented = false
    @State private var dragBaselineStart: Date?
    @State private var dragBaselineEnd: Date?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                labelBody(width: proxy.size.width)

                if proxy.size.width < 52 {
                    Capsule()
                        .fill(segment.label.tint.opacity(0.72))
                        .frame(width: 4, height: 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                if isEditingEnabled {
                    resizeHandle(edge: .leading)
                        .frame(maxHeight: .infinity, alignment: .leading)

                    resizeHandle(edge: .trailing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                }
            }
        }
        .onChange(of: isEditingEnabled) { _, enabled in
            if !enabled, isHovering {
                NSCursor.arrow.set()
                isHovering = false
            }
        }
    }

    private func labelBody(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(segment.label.tint.opacity(isEditingEnabled ? 0.14 : 0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(segment.label.tint.opacity(isEditingEnabled ? 0.86 : 0.72), lineWidth: isEditingEnabled ? 1.2 : 1)
            )
            .overlay(alignment: .leading) {
                if width >= 52 {
                    Text(segment.label.title)
                        .productivityFont(.noteStrong)
                        .foregroundStyle(segment.label.tint.opacity(0.92))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, isEditingEnabled ? 12 : 7)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: width, alignment: .leading)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEditingEnabled else { return }
                isLabelPickerPresented = true
            }
            .onHover { hovering in
                guard isEditingEnabled else { return }
                isHovering = hovering
            }
            .popover(isPresented: $isLabelPickerPresented, arrowEdge: .bottom) {
                labelPicker
            }
            .help(isEditingEnabled ? "Click to relabel. Drag either edge to resize." : "Turn on Edit Labels to adjust this label.")
            .accessibilityLabel(segment.label.title)
    }

    private func resizeHandle(edge: TimelineLabelResizeEdge) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 12)
            .overlay(alignment: edge == .leading ? .leading : .trailing) {
                Capsule()
                    .fill(segment.label.tint.opacity(0.82))
                    .frame(width: 3, height: 14)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let baselineStart = dragBaselineStart ?? segment.startDate
                        let baselineEnd = dragBaselineEnd ?? segment.endDate
                        dragBaselineStart = baselineStart
                        dragBaselineEnd = baselineEnd
                        resizeAction(edge, baselineStart, baselineEnd, value.translation.width)
                    }
                    .onEnded { _ in
                        resizeEndAction()
                        dragBaselineStart = nil
                        dragBaselineEnd = nil
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .help(edge == .leading ? "Drag to adjust start" : "Drag to adjust end")
    }

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set label")
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            ForEach(ActivityLabel.allCases) { label in
                Button {
                    labelChangeAction(label)
                    isLabelPickerPresented = false
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(label.tint)
                            .frame(width: 8, height: 8)
                        Text(label.title)
                        if label == segment.label {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 190)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }
}

private enum TimelineFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private struct TimelineTick {
    let offset: Double
    let label: String
}
