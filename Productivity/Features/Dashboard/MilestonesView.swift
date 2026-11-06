import SwiftUI

struct MilestonesView: View {
    let todaySegments: [ActivitySegment]
    let historicalSegments: [ActivitySegment]
    let focusCycles: Int
    let calendarBoardStore: CalendarBoardStore
    @Environment(\.productivityTextScale) private var textScale

    private var metrics: MilestoneMetrics {
        MilestoneMetrics(
            todaySegments: todaySegments,
            historicalSegments: historicalSegments,
            focusCycles: focusCycles
        )
    }

    private var goalSummary: GoalBoardSummary {
        GoalBoardSummary(goals: calendarBoardStore.goals, pins: calendarBoardStore.pins)
    }

    private var items: [MilestoneItem] {
        let metricsSnapshot = metrics.snapshot
        let completedGoalCount = goalSummary.completedGoalCount

        return [
            MilestoneItem(
                title: "Streak",
                value: "\(metricsSnapshot.streakDays)",
                unit: metricsSnapshot.streakDays == 1 ? "day" : "days",
                detail: metricsSnapshot.streakDays > 0 ? "Productive activity today" : "Start with one productive app",
                systemImage: "flame",
                tint: Color(red: 0.92, green: 0.48, blue: 0.24)
            ),
            MilestoneItem(
                title: "Max Focus Session",
                value: DurationFormatting.abbreviated(metricsSnapshot.maxFocusSession),
                unit: "",
                detail: metricsSnapshot.maxFocusSession > 0 ? "Longest productive stretch" : "No focus session yet",
                systemImage: "scope",
                tint: ActivityLabel.productive.tint
            ),
            MilestoneItem(
                title: "Focus Cycles",
                value: "\(focusCycles)",
                unit: focusCycles == 1 ? "cycle" : "cycles",
                detail: "Completed Pomodoro focus blocks",
                systemImage: "timer",
                tint: ProductivityTheme.accent
            ),
            MilestoneItem(
                title: "Completed Goals",
                value: "\(completedGoalCount)",
                unit: completedGoalCount == 1 ? "goal" : "goals",
                detail: completedGoalCount > 0 ? "Goal Board targets reached" : "Mark goal days on the Board",
                systemImage: "checkmark.seal",
                tint: ActivityLabel.productive.tint
            ),
            MilestoneItem(
                title: "Top App",
                value: metricsSnapshot.topProductiveApp ?? "None",
                unit: "",
                detail: metricsSnapshot.topProductiveApp == nil ? "No productive app captured" : "Most productive time logged",
                systemImage: "app.badge",
                tint: Color(red: 0.32, green: 0.58, blue: 0.92)
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Milestones", systemImage: "flag.checkered")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Spacer()

                Text("Built from local activity")
                    .productivityFont(.captionMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    milestoneCards
                }

                LazyVGrid(columns: compactColumns, spacing: 12) {
                    milestoneCards
                }
            }
        }
        .padding(18 * textScale)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }

    private var milestoneCards: some View {
        ForEach(items) { item in
            MilestoneCard(item: item)
        }
    }

    private var compactColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 190 * textScale), spacing: 12 * textScale, alignment: .top)]
    }
}

private struct MilestoneItem: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let unit: String
    let detail: String
    let systemImage: String
    let tint: Color
}

private struct MilestoneCard: View {
    let item: MilestoneItem
    @Environment(\.productivityTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .productivityFont(.controlIcon)
                    .foregroundStyle(item.tint)
                    .frame(width: 24, height: 24)
                    .background(item.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text(item.title)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.value)
                    .productivityFont(.metric)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)

                if !item.unit.isEmpty {
                    Text(item.unit)
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .lineLimit(1)
                }
            }

            Text(item.detail)
                .productivityFont(.note)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .lineLimit(1)
                .help(item.detail)
        }
        .padding(12 * textScale)
        .frame(maxWidth: .infinity, minHeight: 108 * textScale, alignment: .topLeading)
        .background(ProductivityTheme.subtleBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.tint.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct MilestoneMetrics {
    let todaySegments: [ActivitySegment]
    let historicalSegments: [ActivitySegment]
    let focusCycles: Int

    var snapshot: MilestoneMetricsSnapshot {
        let now = Date()
        let productiveTodaySegments = productiveSegments(from: todaySegments, upTo: now)
        let productiveHistoricalSegments = productiveSegments(from: historicalSegments, upTo: now)
        return MilestoneMetricsSnapshot(
            streakDays: streakDays(from: productiveHistoricalSegments),
            maxFocusSession: maxFocusSession(from: productiveTodaySegments),
            topProductiveApp: topProductiveApp(from: productiveTodaySegments)
        )
    }

    private func streakDays(from productiveSegments: [ActivitySegment]) -> Int {
        let calendar = Calendar.current
        let productiveDays = Set(productiveSegments.map { calendar.startOfDay(for: $0.startDate) })
        var day = calendar.startOfDay(for: Date())
        var streak = 0

        while productiveDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }

        return streak
    }

    private func maxFocusSession(from productiveSegments: [ActivitySegment]) -> TimeInterval {
        let intervals = productiveSegments
            .compactMap(\.safeInterval)
            .sorted { $0.start < $1.start }

        guard let firstInterval = intervals.first else { return 0 }

        var currentStart = firstInterval.start
        var currentEnd = firstInterval.end
        var longest: TimeInterval = firstInterval.duration

        for interval in intervals.dropFirst() {
            if interval.start <= currentEnd {
                currentEnd = max(currentEnd, interval.end)
            } else {
                longest = max(longest, currentEnd.timeIntervalSince(currentStart))
                currentStart = interval.start
                currentEnd = interval.end
            }
        }

        return max(longest, currentEnd.timeIntervalSince(currentStart))
    }

    private func topProductiveApp(from productiveSegments: [ActivitySegment]) -> String? {
        let totalsByApp = productiveSegments.reduce(into: [String: TimeInterval]()) { totals, segment in
            totals[segment.appName, default: 0] += segment.duration
        }

        return totalsByApp.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }

            return lhs.value < rhs.value
        }?.key
    }

    private func productiveSegments(from segments: [ActivitySegment], upTo now: Date) -> [ActivitySegment] {
        segments.compactMap { segment in
            guard !segment.isLifecycleContext else { return nil }
            guard !segment.isSleepEvent else { return nil }
            guard segment.label.commonRollup == .productive else { return nil }
            guard segment.startDate < now else { return nil }
            let endDate = min(segment.endDate, now)
            guard endDate > segment.startDate else { return nil }
            guard endDate != segment.endDate else { return segment }
            return ActivitySegment(
                id: segment.id,
                appName: segment.appName,
                bundleIdentifier: segment.bundleIdentifier,
                title: segment.title,
                userDescription: segment.userDescription,
                startDate: segment.startDate,
                endDate: endDate,
                category: segment.category,
                label: segment.label,
                productivityScore: segment.productivityScore
            )
        }
    }
}

private struct MilestoneMetricsSnapshot {
    let streakDays: Int
    let maxFocusSession: TimeInterval
    let topProductiveApp: String?
}

#if DEBUG
#Preview {
    ScrollView {
        MilestonesView(
            todaySegments: ActivitySegment.sampleDay,
            historicalSegments: ActivitySegment.sampleHistory,
            focusCycles: 3,
            calendarBoardStore: CalendarBoardStore()
        )
            .padding(28)
    }
    .background(ProductivityTheme.background)
    .frame(width: 1120, height: 280)
    .preferredColorScheme(.dark)
}
#endif
