import Foundation
import WidgetKit

@MainActor
enum ProductivityWidgetSnapshotWriter {
    static func update(
        from viewModel: DashboardViewModel,
        calendarBoardStore: CalendarBoardStore,
        pomodoroViewModel: PomodoroViewModel,
        isTrackingEnabled: Bool
    ) {
        let now = Date()
        let overview = viewModel.overview
        let latestSegment = latestDisplaySegment(in: overview.segments, now: now)
        let pins = calendarBoardStore.pins
        let snapshot = ProductivityWidgetSnapshot(
            updatedAt: now,
            productivityPercentage: Int((overview.productivityRatio * 100).rounded()),
            productiveMinutes: max(0, Int(overview.productiveTime / 60)),
            trackedMinutes: max(0, Int(overview.totalTrackedTime / 60)),
            currentTrackingTitle: currentTrackingTitle(for: latestSegment, status: viewModel.trackingStatus, isTrackingEnabled: isTrackingEnabled),
            currentTrackingSubtitle: currentTrackingSubtitle(for: latestSegment, status: viewModel.trackingStatus, isTrackingEnabled: isTrackingEnabled),
            isTrackingEnabled: isTrackingEnabled,
            trackingStatusTitle: trackingStatusTitle(for: viewModel.trackingStatus, isTrackingEnabled: isTrackingEnabled),
            pomodoroPhaseTitle: pomodoroViewModel.phase.title,
            pomodoroRemainingSeconds: pomodoroViewModel.remainingSeconds,
            pomodoroTotalSeconds: pomodoroViewModel.totalSeconds,
            isPomodoroRunning: pomodoroViewModel.isRunning,
            pomodoroUpdatedAt: now,
            completedPomodorosToday: pomodoroViewModel.completedFocusSessions,
            goals: goalSnapshots(from: calendarBoardStore.goals, pins: pins, calendar: .current)
        )

        guard let previousSnapshot = ProductivityWidgetSnapshot.load() else {
            snapshot.save()
            WidgetCenter.shared.reloadTimelines(ofKind: ProductivityWidgetSnapshot.overviewWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: ProductivityWidgetSnapshot.todayGoalsWidgetKind)
            return
        }

        guard previousSnapshot.hasMeaningfulDisplayChange(from: snapshot) else { return }

        if snapshot.save() {
            WidgetCenter.shared.reloadTimelines(ofKind: ProductivityWidgetSnapshot.overviewWidgetKind)
            WidgetCenter.shared.reloadTimelines(ofKind: ProductivityWidgetSnapshot.todayGoalsWidgetKind)
        }
    }

    private static func latestDisplaySegment(in segments: [ActivitySegment], now: Date) -> ActivitySegment? {
        segments.reduce(nil) { latest, segment in
            guard segment.startDate <= now else { return latest }
            guard let latest else { return segment }
            return segment.endDate > latest.endDate ? segment : latest
        }
    }

    private static func currentTrackingTitle(
        for segment: ActivitySegment?,
        status: ActivityTrackingStatus,
        isTrackingEnabled: Bool
    ) -> String {
        guard isTrackingEnabled else { return "Paused" }
        guard status != .waitingForTrackedApp else { return "Waiting for app" }
        guard let appName = segment?.appName.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty else {
            return "No activity yet"
        }
        return appName
    }

    private static func currentTrackingSubtitle(
        for segment: ActivitySegment?,
        status: ActivityTrackingStatus,
        isTrackingEnabled: Bool
    ) -> String {
        guard isTrackingEnabled else { return "Tracking is off" }
        guard status != .starting else { return "Starting tracker" }
        guard let segment else { return trackingStatusTitle(for: status, isTrackingEnabled: isTrackingEnabled) }
        return segment.label.title
    }

    private static func trackingStatusTitle(for status: ActivityTrackingStatus, isTrackingEnabled: Bool) -> String {
        guard isTrackingEnabled else { return "Paused" }
        switch status {
        case .paused: return "Paused"
        case .starting: return "Starting"
        case .tracking: return "Tracking"
        case .waitingForTrackedApp: return "Waiting"
        }
    }

    private static func goalSnapshots(
        from goals: [CalendarActivityGoal],
        pins: [String: [String]],
        calendar: Calendar
    ) -> [ProductivityWidgetGoalSnapshot] {
        let todayKey = EmojiPinStorage.key(for: Date(), calendar: calendar)
        let todayMarkers = Set((pins[todayKey] ?? []).map(CalendarMarker.normalizedID))
        let datedPins = pins.compactMap { key, ids -> (date: Date, markerIDs: Set<String>)? in
            guard let date = EmojiPinStorage.date(for: key, calendar: calendar) else { return nil }
            return (date, Set(ids.map(CalendarMarker.normalizedID)))
        }

        return goals.prefix(6).map { goal in
            let interval = goal.period.interval(containing: Date(), calendar: calendar)
            let completedCount = datedPins.reduce(0) { count, pins in
                guard let interval,
                      interval.contains(pins.date),
                      pins.markerIDs.contains(CalendarMarker.normalizedID(for: goal.markerID)) else {
                    return count
                }
                return count + 1
            }

            return ProductivityWidgetGoalSnapshot(
                goalID: goal.id,
                markerID: CalendarMarker.normalizedID(for: goal.markerID),
                name: goal.name,
                symbol: symbol(for: goal),
                completedCount: completedCount,
                targetCount: goal.targetCount,
                periodTitle: goal.period.shortUnitTitle,
                isDoneToday: todayMarkers.contains(CalendarMarker.normalizedID(for: goal.markerID))
            )
        }
    }

    private static func symbol(for goal: CalendarActivityGoal) -> String {
        if let customSymbol = goal.symbol?.trimmingCharacters(in: .whitespacesAndNewlines), !customSymbol.isEmpty {
            return customSymbol
        }

        return CalendarMarker.allMarkers.first { $0.id == CalendarMarker.normalizedID(for: goal.markerID) }?.systemImage ?? "target"
    }
}
