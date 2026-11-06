import SwiftUI

struct DashboardView: View {
    private let environment: AppEnvironment
    @Environment(\.productivityTextScale) private var textScale
    @Environment(\.productivityIsFullScreen) private var isFullScreen
    private let viewModel: DashboardViewModel
    @AppStorage("dashboard.selection") private var selection: DashboardRoute = .today
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(AppPreferenceKeys.isDailyFocusHeaderEnabled) private var isDailyFocusHeaderEnabled = true

    init(environment: AppEnvironment) {
        self.environment = environment
        self.viewModel = environment.dashboardViewModel
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(
                    min: 150 * textScale,
                    ideal: 250 * textScale,
                    max: 320 * textScale
                )
        } detail: {
            detailView
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(.smooth(duration: 0.24), value: selection)
        .task {
            await viewModel.loadPersistedSegmentsIfNeeded()
        }
        .onChange(of: environment.lifecycleRefreshID) {
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                await viewModel.reloadPersistedSegments()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .today:
            todayView
        case .insights:
            WeeklyInsightsView(
                segments: viewModel.insightSegments,
                labelSegments: viewModel.labelSegments,
                calendarBoardStore: environment.calendarBoardStore
            ) { interval in
                await viewModel.loadInsightData(for: interval)
            }
        case .analytics:
            AnalyticsView(segments: viewModel.insightMetricSegments)
        case .calendar:
            EmojiCalendarView(
                calendarBoardStore: environment.calendarBoardStore,
                onBoardChanged: environment.writeWidgetSnapshotNow
            )
        case .pomodoro:
            PomodoroView(viewModel: environment.pomodoroViewModel)
        case .settings:
            SettingsView(segments: viewModel.overview.segments)
        }
    }

    private var todayView: some View {
        GeometryReader { proxy in
            let contentWidth = ProductivityTheme.contentWidth(for: proxy.size.width, isFullScreen: isFullScreen)
            let contentPadding = ProductivityTheme.contentPadding(for: proxy.size.width, isFullScreen: isFullScreen) * textScale

            ScrollView {
                VStack(alignment: .leading, spacing: 24 * textScale) {
                    if isDailyFocusHeaderEnabled {
                        DailyQuoteHeaderView()
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    DashboardHeaderView(
                        overview: viewModel.overview,
                        trackingStatus: viewModel.trackingStatus,
                        metricSegments: viewModel.todayMetricSegments
                    )
                    InsightStripView(insights: todayInsights)
                    if viewModel.isNotificationPermissionDenied {
                        notificationPermissionWarning
                    }
                    timelineSection
                    secondaryPanels
                    activityAuditSection
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(contentPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(ProductivityTheme.background)
        }
    }

    private var todayInsights: [InsightSummary] {
        let goalSummary = GoalBoardSummary(
            goals: environment.calendarBoardStore.goals,
            pins: environment.calendarBoardStore.pins,
            referenceDate: viewModel.overview.date
        )
        let momentum = todayMomentum

        return [
            InsightSummary(
                title: "Productive",
                value: DurationFormatting.abbreviated(viewModel.overview.productiveTime),
                trend: "\(Int(viewModel.overview.productivityRatio * 100))% of tracked time",
                category: .focus
            ),
            InsightSummary(
                title: "Time Tracked",
                value: DurationFormatting.abbreviated(viewModel.overview.totalTrackedTime),
                trend: trackedDayCoverageTrend,
                category: .system
            ),
            InsightSummary(
                title: "Goal Progress",
                value: goalProgressValue(from: goalSummary),
                trend: goalProgressTrend(from: goalSummary),
                category: .research
            ),
            InsightSummary(
                title: "Current Momentum",
                value: DurationFormatting.abbreviated(momentum.duration),
                trend: momentum.trend,
                category: .focus
            )
        ]
    }

    private var trackedDayCoverageTrend: String {
        let referenceDate = viewModel.overview.date
        let elapsedSeconds = max(1, referenceDate.timeIntervalSince(Calendar.current.startOfDay(for: referenceDate)))
        let ratio = min(1.0, viewModel.overview.totalTrackedTime / elapsedSeconds)
        return "\(Int(ratio * 100))% of your day covered"
    }

    private var todayMomentum: TodayMomentumSnapshot {
        let now = viewModel.overview.date
        let productiveIntervals = productiveIntervals(upTo: now)
        guard !productiveIntervals.isEmpty else {
            return TodayMomentumSnapshot(duration: 0, trend: "No productive stretch yet")
        }

        let longestDuration = productiveIntervals.map(\.duration).max() ?? 0
        if let activeInterval = productiveIntervals.last,
           activeInterval.end >= now.addingTimeInterval(-90) {
            return TodayMomentumSnapshot(
                duration: activeInterval.duration,
                trend: "Active now"
            )
        }

        return TodayMomentumSnapshot(
            duration: longestDuration,
            trend: "Best stretch today"
        )
    }

    private func goalProgressValue(from summary: GoalBoardSummary) -> String {
        guard !summary.goals.isEmpty else { return "No goals" }
        return "\(summary.completedGoalCount)/\(summary.goals.count)"
    }

    private func goalProgressTrend(from summary: GoalBoardSummary) -> String {
        guard !summary.goals.isEmpty else { return "Board summary" }
        return summary.goals.count == 1 ? "1 active target on the board" : "\(summary.goals.count) active targets on the board"
    }

    private func productiveIntervals(upTo now: Date) -> [DateInterval] {
        let productiveSegments = viewModel.todayMetricSegments.compactMap { segment -> DateInterval? in
            guard !segment.isLifecycleContext else { return nil }
            guard !segment.isSleepEvent else { return nil }
            guard segment.label.commonRollup == .productive else { return nil }
            guard segment.startDate < now else { return nil }

            let endDate = min(segment.endDate, now)
            guard endDate > segment.startDate else { return nil }
            return DateInterval(start: segment.startDate, end: endDate)
        }
        .sorted { $0.start < $1.start }

        guard let firstInterval = productiveSegments.first else { return [] }
        var mergedIntervals = [firstInterval]

        for interval in productiveSegments.dropFirst() {
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

    private var notificationPermissionWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundStyle(ProductivityTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notification Permission Required")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text("Event alerts won't fire until notifications are enabled for this app.")
                    .productivityFont(.note)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(12)
        .background(ProductivityTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(ProductivityTheme.accent.opacity(0.22), lineWidth: 1))
    }

    private var timelineSection: some View {
        TimelineEditorView(
            segments: viewModel.overview.segments,
            events: viewModel.manualEvents,
            storedLabelSegments: viewModel.labelSegments,
            onAddEvent: { event in
                viewModel.addManualEvent(event)
            },
            onUpdateEvent: { event in
                viewModel.updateManualEvent(event)
            },
            onDeleteEvent: { event in
                viewModel.deleteManualEvent(event)
            }
        ) { updatedLabelSegments in
            viewModel.updateLabelSegments(updatedLabelSegments)
        }
    }

    private var secondaryPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                GoalTodayPanel(calendarBoardStore: environment.calendarBoardStore)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                MilestonesView(
                    todaySegments: viewModel.todayMetricSegments,
                    historicalSegments: viewModel.insightMetricSegments,
                    focusCycles: environment.pomodoroViewModel.completedFocusSessions,
                    calendarBoardStore: environment.calendarBoardStore
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 16) {
                GoalTodayPanel(calendarBoardStore: environment.calendarBoardStore)
                MilestonesView(
                    todaySegments: viewModel.todayMetricSegments,
                    historicalSegments: viewModel.insightMetricSegments,
                    focusCycles: environment.pomodoroViewModel.completedFocusSessions,
                    calendarBoardStore: environment.calendarBoardStore
                )
            }
        }
    }

    private var activityAuditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Recent Audit")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary.opacity(0.82))
                ProductivityInfoHint(message: "Inspect or remove captured items. This is secondary to the main timeline and daily dashboard.")
            }

            ActivityStreamListView(segments: viewModel.overview.segments) { segment in
                await viewModel.deleteSegment(segment)
            }
            .opacity(0.92)
        }
        .padding(16)
        .background(ProductivityTheme.subtleBackground.opacity(0.42), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ProductivityTheme.border.opacity(0.24), lineWidth: 1)
        )
    }

}

private struct TodayMomentumSnapshot {
    let duration: TimeInterval
    let trend: String
}

#if DEBUG
#Preview {
    DashboardView(environment: AppEnvironment.preview())
        .frame(width: 1100, height: 760)
        .preferredColorScheme(.dark)
}
#endif
