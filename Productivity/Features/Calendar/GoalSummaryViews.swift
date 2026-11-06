import SwiftUI

struct GoalTodayPanel: View {
    let calendarBoardStore: CalendarBoardStore
    @Environment(\.productivityTextScale) private var textScale

    private var summary: GoalBoardSummary {
        GoalBoardSummary(goals: calendarBoardStore.goals, pins: calendarBoardStore.pins)
    }

    var body: some View {
        let items = summary.items
        let completedGoalCount = items.filter { $0.progress.isComplete }.count

        VStack(alignment: .leading, spacing: 14 * textScale) {
            HStack {
                Label("Active Goals", systemImage: "target")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Spacer()

                Text(summary.periodStatusText(completedGoalCount: completedGoalCount))
                    .productivityFont(.noteStrong)
                    .foregroundStyle(completedGoalCount == summary.goals.count && !summary.goals.isEmpty ? ActivityLabel.productive.tint : ProductivityTheme.textSecondary)
            }

            if items.isEmpty {
                GoalEmptyStateRow(title: "No active targets", detail: "Create weekly or monthly goals on the Board, then mark concrete wins here as you go.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10 * textScale) {
                    ForEach(items) { item in
                        GoalTodayCard(item: item)
                    }
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

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260 * textScale, maximum: 360 * textScale), spacing: 10 * textScale, alignment: .top)]
    }
}

struct GoalInsightsPanel: View {
    let scope: GoalInsightScope
    let referenceDate: Date
    let calendarBoardStore: CalendarBoardStore

    init(scope: GoalInsightScope = .current, referenceDate: Date = Date(), calendarBoardStore: CalendarBoardStore) {
        self.scope = scope
        self.referenceDate = referenceDate
        self.calendarBoardStore = calendarBoardStore
    }

    private var summary: GoalBoardSummary {
        GoalBoardSummary(
            goals: calendarBoardStore.goals,
            pins: calendarBoardStore.pins,
            scope: scope,
            referenceDate: referenceDate
        )
    }

    var body: some View {
        let items = summary.items
        let completedGoalCount = items.filter { $0.progress.isComplete }.count

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(scope.title, systemImage: "target")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Spacer()

                Text(summary.periodStatusText(completedGoalCount: completedGoalCount))
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            if items.isEmpty {
                GoalEmptyStateRow(title: "No goal data", detail: "Goal progress appears here after you add goals on the Board.")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        GoalInsightRow(item: item)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 10, alignment: .top)]
    }
}

enum GoalInsightScope {
    case current
    case week
    case month
    case year

    var title: String {
        switch self {
        case .current: "Goal Progress"
        case .week: "Weekly Goals"
        case .month: "Monthly Goals"
        case .year: "Yearly Goals"
        }
    }
}

struct GoalBoardSummary {
    let goals: [CalendarActivityGoal]
    let pins: [String: [String]]
    private let scope: GoalInsightScope
    private let referenceDate: Date
    private let calendar: Calendar
    private let normalizedPinsByKey: [String: Set<String>]
    private let datedPins: [DatedGoalPins]
    private static let markersByID = Dictionary(
        uniqueKeysWithValues: CalendarMarker.allMarkers.map { ($0.id, $0) }
    )

    init(
        goals: [CalendarActivityGoal],
        pins: [String: [String]],
        scope: GoalInsightScope = .current,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.goals = goals
        self.pins = pins
        self.scope = scope
        self.referenceDate = referenceDate
        self.calendar = calendar
        self.normalizedPinsByKey = pins.mapValues { Self.normalizedPinIDSet($0) }
        self.datedPins = pins.compactMap { key, ids in
            guard let date = EmojiPinStorage.date(for: key, calendar: calendar) else { return nil }
            return DatedGoalPins(date: date, markerIDs: Self.normalizedPinIDSet(ids))
        }
    }

    var items: [GoalSummaryItem] {
        goals.map { goal in
            let marker = marker(for: goal)
            let progress = progress(for: goal)
            let isPinnedToday = todayPinIDs.contains(goal.markerID)
            return GoalSummaryItem(
                goal: goal,
                marker: marker,
                symbol: symbol(for: goal),
                progress: progress,
                isPinnedToday: isPinnedToday,
                periodTitle: periodTitle(for: goal),
                scope: scope
            )
        }
    }

    var completedGoalCount: Int {
        goals.filter { progress(for: $0).isComplete }.count
    }

    var markedTodayGoalCount: Int {
        goals.filter { todayPinIDs.contains($0.markerID) }.count
    }

    var periodStatusText: String {
        periodStatusText(completedGoalCount: completedGoalCount)
    }

    var todayStatusText: String {
        guard !goals.isEmpty else { return "No goals" }
        return "\(markedTodayGoalCount) of \(goals.count) marked today"
    }

    func periodStatusText(completedGoalCount: Int) -> String {
        guard !goals.isEmpty else { return "No goals" }
        return "\(completedGoalCount) of \(goals.count) complete"
    }

    private var todayPinIDs: Set<String> {
        let key = EmojiPinStorage.key(for: referenceDate, calendar: calendar)
        return normalizedPinsByKey[key] ?? []
    }

    private func progress(for goal: CalendarActivityGoal) -> GoalProgress {
        guard let interval = interval(for: goal) else {
            return GoalProgress(completedCount: 0, targetCount: goal.targetCount)
        }

        let completedCount = datedPins.reduce(0) { count, datedPin in
            guard interval.contains(datedPin.date),
                  datedPin.markerIDs.contains(goal.markerID) else {
                return count
            }

            return count + 1
        }

        return GoalProgress(completedCount: completedCount, targetCount: targetCount(for: goal, in: interval))
    }

    private func interval(for goal: CalendarActivityGoal) -> DateInterval? {
        let today = Date()
        let baseInterval: DateInterval?
        switch scope {
        case .current:
            baseInterval = goal.period.progressInterval(displayedMonth: referenceDate, calendar: calendar)
        case .week:
            baseInterval = calendar.mondayBased.dateInterval(of: .weekOfYear, for: referenceDate)
        case .month:
            baseInterval = calendar.dateInterval(of: .month, for: referenceDate)
        case .year:
            baseInterval = calendar.dateInterval(of: .year, for: referenceDate)
        }

        guard let baseInterval else { return nil }
        guard baseInterval.contains(today) else { return baseInterval }
        guard today > baseInterval.start else { return nil }
        return DateInterval(start: baseInterval.start, end: today)
    }

    private func targetCount(for goal: CalendarActivityGoal, in interval: DateInterval) -> Int {
        switch scope {
        case .current:
            return goal.targetCount
        case .week:
            return goal.period == .weekly ? goal.targetCount : scaledMonthlyTarget(for: goal, in: interval)
        case .month:
            switch goal.period {
            case .weekly:
                return goal.targetCount * max(1, completedWeekCount(in: interval))
            case .monthly:
                return goal.targetCount
            }
        case .year:
            switch goal.period {
            case .weekly:
                return goal.targetCount * max(1, completedWeekCount(in: interval))
            case .monthly:
                return goal.targetCount * max(1, completedMonthCount(in: interval))
            }
        }
    }

    private func scaledMonthlyTarget(for goal: CalendarActivityGoal, in interval: DateInterval) -> Int {
        guard goal.period == .monthly,
              let monthInterval = calendar.dateInterval(of: .month, for: interval.start),
              monthInterval.duration > 0 else {
            return goal.targetCount
        }

        let ratio = interval.duration / monthInterval.duration
        return max(1, Int(ceil(Double(goal.targetCount) * ratio)))
    }

    private func completedWeekCount(in interval: DateInterval) -> Int {
        bucketCount(in: interval, component: .weekOfYear, using: calendar.mondayBased)
    }

    private func completedMonthCount(in interval: DateInterval) -> Int {
        bucketCount(in: interval, component: .month, using: calendar)
    }

    private func bucketCount(in interval: DateInterval, component: Calendar.Component, using calendar: Calendar) -> Int {
        var count = 0
        var cursor = interval.start
        while cursor < interval.end {
            count += 1
            guard let nextDate = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            cursor = nextDate
        }
        return count
    }

    private func marker(for goal: CalendarActivityGoal) -> CalendarMarker {
        if let customMarker = CalendarMarker.custom(for: goal) {
            return customMarker
        }

        return Self.markersByID[goal.markerID] ?? CalendarMarker.allMarkers[0]
    }

    private func symbol(for goal: CalendarActivityGoal) -> String? {
        guard goal.isCustomMarker else { return nil }
        return goal.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func periodTitle(for goal: CalendarActivityGoal) -> String {
        if scope != .current {
            return switch scope {
            case .current: ""
            case .week: "Selected week"
            case .month: goal.period == .weekly ? "Weekly goal rollup" : "Selected month"
            case .year: goal.period == .weekly ? "Weekly goal rollup" : "Monthly goal rollup"
            }
        }

        switch goal.period {
        case .weekly:
            return "This week"
        case .monthly:
            return "This month"
        }
    }

    private static func normalizedPinIDSet(_ ids: [String]) -> Set<String> {
        Set(ids.map { CalendarMarker.normalizedID(for: $0) })
    }
}

private struct DatedGoalPins {
    let date: Date
    let markerIDs: Set<String>
}

struct GoalSummaryItem: Identifiable {
    let goal: CalendarActivityGoal
    let marker: CalendarMarker
    let symbol: String?
    let progress: GoalProgress
    let isPinnedToday: Bool
    let periodTitle: String
    let scope: GoalInsightScope

    var id: UUID { goal.id }

    var remainingCount: Int {
        max(0, progress.targetCount - progress.completedCount)
    }

    var periodProgressText: String {
        switch scope {
        case .current:
            "\(progress.completedCount) of \(progress.targetCount) \(goal.period.shortUnitTitle)"
        case .week:
            "\(progress.completedCount) of \(progress.targetCount) selected week"
        case .month:
            "\(progress.completedCount) of \(progress.targetCount) selected month"
        case .year:
            "\(progress.completedCount) of \(progress.targetCount) selected year"
        }
    }

    var todayBadgeText: String? {
        isPinnedToday ? "Marked today" : nil
    }
}

private struct GoalTodayCard: View {
    let item: GoalSummaryItem
    @Environment(\.productivityTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * textScale) {
            HStack(alignment: .top, spacing: 12 * textScale) {
                PersonalizedMarkerGlyph(marker: item.marker, symbol: item.symbol, size: 28, iconSize: 13, isSelected: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.goal.name)
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)

                    Text(progressSummaryText)
                        .productivityFont(.note)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            Label(item.todayBadgeText ?? "Marked today", systemImage: "checkmark.circle.fill")
                .productivityFont(.captionStrong)
                .foregroundStyle(ActivityLabel.productive.tint)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .opacity(item.todayBadgeText == nil ? 0 : 1)
                .accessibilityHidden(item.todayBadgeText == nil)

            GoalMiniProgressBar(item: item)
        }
        .padding(12 * textScale)
        .frame(maxWidth: .infinity, minHeight: 110 * textScale, alignment: .topLeading)
        .background(ProductivityTheme.subtleBackground.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.marker.tint.opacity(item.isPinnedToday ? 0.46 : 0.18), lineWidth: 1)
        )
    }

    private var progressSummaryText: String {
        "\(item.periodTitle) · \(item.progress.completedCount)/\(item.progress.targetCount)"
    }
}

private struct GoalInsightRow: View {
    let item: GoalSummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PersonalizedMarkerGlyph(marker: item.marker, symbol: item.symbol, size: 34, iconSize: 16, isSelected: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.goal.name)
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                    Text(item.periodTitle)
                        .productivityFont(.captionMedium)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Spacer()

                Text("\(item.progress.completedCount)/\(item.progress.targetCount)")
                    .font(ProductivityTypography.font(.bodyMonospaced, weight: .semibold))
                    .foregroundStyle(ProductivityTheme.textPrimary)
            }

            GoalMiniProgressBar(item: item)
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.marker.tint.opacity(item.progress.isComplete ? 0.48 : 0.18), lineWidth: 1)
        )
    }
}

private struct GoalMiniProgressBar: View {
    let item: GoalSummaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("\(item.progress.completedCount) done")
                Spacer()
                Text(item.progress.isComplete ? "Complete" : "\(item.remainingCount) to go")
            }
            .font(ProductivityTypography.font(.noteMonospaced, weight: .medium))
            .foregroundStyle(item.progress.isComplete ? ActivityLabel.productive.tint : ProductivityTheme.textSecondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ProductivityTheme.subtleBackground)
                    Capsule()
                        .fill(item.marker.tint)
                        .frame(width: proxy.size.width * item.progress.fraction)
                }
            }
            .frame(height: 7)
        }
    }
}

private struct GoalEmptyStateRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text(detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.subtleBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Calendar {
    var mondayBased: Calendar {
        var calendar = self
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
