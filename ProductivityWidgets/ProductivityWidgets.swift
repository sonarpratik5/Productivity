import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Entry & Provider

struct ProductivityWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ProductivityWidgetSnapshot
}

struct ProductivityWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProductivityWidgetEntry {
        ProductivityWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ProductivityWidgetEntry) -> Void) {
        completion(ProductivityWidgetEntry(date: Date(), snapshot: snapshot(for: context)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductivityWidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = snapshot(for: context)
        let entry = ProductivityWidgetEntry(date: now, snapshot: snapshot)
        let nextRefresh = nextRefresh(after: now, snapshot: snapshot)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func snapshot(for context: Context) -> ProductivityWidgetSnapshot {
        context.isPreview ? .placeholder : (ProductivityWidgetSnapshot.load() ?? .empty)
    }

    private func nextRefresh(after now: Date, snapshot: ProductivityWidgetSnapshot) -> Date {
        let calendar = Calendar.current
        let nextDay = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 5),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(24 * 60 * 60)

        guard snapshot.isPomodoroRunning else { return nextDay }

        let pomodoroEndDate = snapshot.pomodoroUpdatedAt.addingTimeInterval(snapshot.pomodoroRemainingSeconds)
        guard pomodoroEndDate > now else { return now.addingTimeInterval(60) }

        return min(pomodoroEndDate.addingTimeInterval(5), nextDay)
    }
}

// MARK: - Widget Definitions

struct ProductivityOverviewWidget: Widget {
    let kind = ProductivityWidgetSnapshot.overviewWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityWidgetProvider()) { entry in
            ProductivityOverviewWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Productivity Overview")
        .description("Focus score, tracked time, and Pomodoro status.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TodayGoalsWidget: Widget {
    static let kind = ProductivityWidgetSnapshot.todayGoalsWidgetKind
    let kind = Self.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivityWidgetProvider()) { entry in
            TodayGoalsWidgetView(entry: entry)
                .containerBackground(WidgetTheme.background, for: .widget)
        }
        .configurationDisplayName("Today's Goals")
        .description("Weekly and monthly goal progress at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Shared Components

private struct ArcProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

private struct StatusDot: View {
    let isActive: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isActive ? Color.green : .secondary)
        }
    }
}

private enum WidgetTheme {
    static let background = Color(red: 0.992, green: 0.987, blue: 0.973)
    static let subtleBackground = Color(red: 0.916, green: 0.945, blue: 0.935)
    static let border = Color(red: 0.788, green: 0.839, blue: 0.820)
    static let textPrimary = Color(red: 0.082, green: 0.180, blue: 0.220)
    static let textSecondary = Color(red: 0.337, green: 0.431, blue: 0.447)
    static let accent = Color(red: 0.176, green: 0.608, blue: 0.561)
}

// MARK: - Overview Widget View

struct ProductivityOverviewWidgetView: View {
    let entry: ProductivityWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemSmall {
            smallLayout
                .widgetURL(URL(string: "focusgrove://today"))
        } else {
            mediumLayout
                .widgetURL(URL(string: "focusgrove://today"))
        }
    }

    // MARK: Small

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Day name is more useful glanceable context than the app name
            HStack(alignment: .center) {
                Text(entry.snapshot.updatedAt, format: .dateTime.weekday(.wide))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusDot(isActive: entry.snapshot.isTrackingEnabled, label: entry.snapshot.trackingStatusTitle)
            }

            Spacer()

            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    ArcProgressRing(progress: productivityFraction, lineWidth: 5, tint: .green)
                    VStack(spacing: 0) {
                        Text("\(entry.snapshot.productivityPercentage)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("%")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatMinutes(entry.snapshot.trackedMinutes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("tracked")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)

                    Spacer().frame(height: 4)

                    // Pill chip makes the Pomodoro section visually distinct and tappable
                    pomodoroChip
                }
            }

            Spacer()

            Divider().opacity(0.3).padding(.bottom, 5)

            HStack(spacing: 4) {
                Circle()
                    .fill(entry.snapshot.isTrackingEnabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 4, height: 4)
                Text(entry.snapshot.currentTrackingTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(entry.snapshot.currentTrackingSubtitle)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Medium

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("FocusGrove")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                StatusDot(isActive: entry.snapshot.isTrackingEnabled, label: entry.snapshot.trackingStatusTitle)
            }

            Spacer()

            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    ArcProgressRing(progress: productivityFraction, lineWidth: 6, tint: .green)
                    ArcProgressRing(progress: pomodoroFraction, lineWidth: 3, tint: .orange)
                        .padding(10)
                    VStack(spacing: 1) {
                        Text("\(entry.snapshot.productivityPercentage)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("% focus")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    metricRow(icon: "clock", label: "Tracked", value: formatMinutes(entry.snapshot.trackedMinutes))
                    pomodoroMetricRow
                    metricRow(icon: "checkmark.circle", label: "Sessions", value: "\(entry.snapshot.completedPomodorosToday) today")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()

            Divider().opacity(0.3).padding(.bottom, 6)

            HStack(spacing: 6) {
                Circle()
                    .fill(entry.snapshot.isTrackingEnabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 5, height: 5)
                Text(entry.snapshot.currentTrackingTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.snapshot.currentTrackingSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Pomodoro Components

    /// Pill-shaped chip for the small layout — background + play/pause icon make it clearly tappable
    private var pomodoroChip: some View {
        let chipColor: Color = entry.snapshot.isPomodoroRunning ? .orange : .secondary
        return Link(destination: URL(string: "focusgrove://pomodoro")!) {
            HStack(spacing: 4) {
                Image(systemName: entry.snapshot.isPomodoroRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(chipColor)
                VStack(alignment: .leading, spacing: 0) {
                    pomodoroTimeLabel
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(chipColor)
                    Text(entry.snapshot.pomodoroPhaseTitle)
                        .font(.system(size: 8))
                        .foregroundStyle(chipColor.opacity(0.75))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(chipColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        }
    }

    /// Interactive Pomodoro row for the medium layout — play/pause icon + chevron signal interactivity
    private var pomodoroMetricRow: some View {
        let isRunning = entry.snapshot.isPomodoroRunning
        return Link(destination: URL(string: "focusgrove://pomodoro")!) {
            HStack(spacing: 6) {
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isRunning ? .orange : .secondary)
                    .frame(width: 12, alignment: .center)
                Text(entry.snapshot.pomodoroPhaseTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(isRunning ? .orange : .secondary)
                Spacer(minLength: 4)
                pomodoroTimeLabel
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isRunning ? .orange : .primary)
                    .monospacedDigit()
                Image(systemName: "chevron.forward")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isRunning ? Color.orange.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: Helpers

    private var productivityFraction: Double {
        Double(entry.snapshot.productivityPercentage) / 100
    }

    private var pomodoroFraction: Double {
        guard entry.snapshot.pomodoroTotalSeconds > 0 else { return 0 }
        return 1 - (currentPomodoroRemainingSeconds / entry.snapshot.pomodoroTotalSeconds)
    }

    private var currentPomodoroRemainingSeconds: TimeInterval {
        guard entry.snapshot.isPomodoroRunning else { return entry.snapshot.pomodoroRemainingSeconds }
        let elapsed = Date().timeIntervalSince(entry.snapshot.pomodoroUpdatedAt)
        return max(0, entry.snapshot.pomodoroRemainingSeconds - elapsed)
    }

    private var pomodoroEndDate: Date {
        entry.snapshot.pomodoroUpdatedAt.addingTimeInterval(entry.snapshot.pomodoroRemainingSeconds)
    }

    private var pomodoroTimeLabel: Text {
        guard entry.snapshot.isPomodoroRunning, pomodoroEndDate > Date() else {
            return Text(pomodoroTimeText)
        }

        return Text(timerInterval: Date()...pomodoroEndDate, countsDown: true)
    }

    private var pomodoroTimeText: String {
        let secs = Int(currentPomodoroRemainingSeconds)
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    private func metricRow(icon: String, label: String, value: String, accent: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(width: 12, alignment: .center)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(accent ?? .primary)
                .monospacedDigit()
        }
    }

    private func formatMinutes(_ value: Int) -> String {
        let h = value / 60, m = value % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - Goals Widget View

struct TodayGoalsWidgetView: View {
    let entry: ProductivityWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            goalHeader

            if entry.snapshot.goals.isEmpty {
                emptyState
            } else {
                Spacer(minLength: 8)
                goalList
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "focusgrove://board"))
    }

    // MARK: Header

    private var goalHeader: some View {
        HStack(alignment: .center) {
            Text(family == .systemSmall ? "Today" : "Goals")
                .font(.system(size: family == .systemSmall ? 11 : 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if !entry.snapshot.goals.isEmpty {
                let allDone = doneTodayCount == entry.snapshot.goals.count
                Text(allDone ? "\(doneTodayCount) of \(entry.snapshot.goals.count) complete" : "\(doneTodayCount) of \(entry.snapshot.goals.count) today")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(allDone ? WidgetTheme.accent : WidgetTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
        }
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "target")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)
                Text("No goals yet")
                    .font(.system(size: 13, weight: .semibold))
                Text("Open FocusGrove → Board to add weekly or monthly goals.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    // MARK: Goal List

    private var goalList: some View {
        VStack(spacing: family == .systemSmall ? 7 : family == .systemLarge ? 9 : 7) {
            ForEach(visibleGoals) { goal in
                goalRow(goal)
            }
        }
    }

    private var visibleGoals: [ProductivityWidgetGoalSnapshot] {
        let limit = family == .systemLarge ? 6 : family == .systemMedium ? 4 : 2
        return Array(entry.snapshot.goals.prefix(limit))
    }

    private var doneTodayCount: Int {
        entry.snapshot.goals.filter { $0.isDoneToday == true }.count
    }

    // MARK: Goal Row

    private func goalRow(_ goal: ProductivityWidgetGoalSnapshot) -> some View {
        let isComplete = goal.completedCount >= goal.targetCount
        let isDoneToday = goal.isDoneToday == true

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                goalGlyph(goal.symbol, isComplete: isComplete, isDoneToday: isDoneToday)
                    .frame(width: goalGlyphSize, height: goalGlyphSize, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.name)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("\(goal.completedCount)/\(goal.targetCount) \(goal.periodTitle)")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .monospacedDigit()
                }

                Spacer(minLength: 4)

                if let goalID = goal.goalID?.uuidString,
                   let markerID = goal.markerID {
                    goalToggleButton(
                        goalID: goalID,
                        markerID: markerID,
                        isDoneToday: isDoneToday
                    )
                } else {
                    Text("\(goal.completedCount)/\(goal.targetCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isDoneToday || isComplete ? WidgetTheme.accent : WidgetTheme.accent.opacity(0.72))
                        .frame(width: geo.size.width * goal.progress)
                }
            }
            .frame(height: 4)
            .invalidatableContent()
        }
        .padding(family == .systemSmall ? 6 : 7)
        .background(WidgetTheme.subtleBackground.opacity(isDoneToday ? 0.72 : 0.48), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isDoneToday || isComplete ? WidgetTheme.accent : WidgetTheme.border).opacity(isDoneToday ? 0.42 : 0.34), lineWidth: 1)
        )
    }

    private func goalToggleButton(goalID: String, markerID: String, isDoneToday: Bool) -> some View {
        Button(intent: CompleteGoalIntent(goalID: goalID, markerID: markerID, isDone: !isDoneToday)) {
            ZStack {
                Circle()
                    .fill(isDoneToday ? WidgetTheme.accent : WidgetTheme.background.opacity(0.92))
                Circle()
                    .stroke(isDoneToday ? WidgetTheme.accent : WidgetTheme.border, lineWidth: 1)
                Image(systemName: isDoneToday ? "checkmark" : "plus")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isDoneToday ? Color.white : WidgetTheme.textSecondary)
            }
            .frame(width: goalToggleSize, height: goalToggleSize)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDoneToday ? "Unmark goal for today" : "Mark goal for today")
    }

    @ViewBuilder
    private func goalGlyph(_ symbol: String, isComplete: Bool, isDoneToday: Bool) -> some View {
        let tint: Color = isDoneToday || isComplete ? WidgetTheme.accent : WidgetTheme.textSecondary
        if symbol.isLikelySystemImageName {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: goalGlyphSize, height: goalGlyphSize)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        } else {
            Text(symbol)
                .font(.system(size: 11))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: goalGlyphSize, height: goalGlyphSize)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    private var goalGlyphSize: CGFloat {
        family == .systemSmall ? 20 : 22
    }

    private var goalToggleSize: CGFloat {
        family == .systemSmall ? 21 : 22
    }
}

// MARK: - Helpers

private extension String {
    var isLikelySystemImageName: Bool {
        !isEmpty && allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
    }
}
