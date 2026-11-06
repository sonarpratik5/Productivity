import Charts
import SwiftUI

private enum InsightPeriod: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    var subtitle: String {
        switch self {
        case .week:
            "See how your attention shifted through the week."
        case .month:
            "Spot patterns across your average working days."
        case .year:
            "See how consistently you protected focus over time."
        }
    }

    var historyGrouping: InsightHistoryGrouping {
        switch self {
        case .week: .day
        case .month: .week
        case .year: .month
        }
    }

    var goalInsightScope: GoalInsightScope {
        switch self {
        case .week: .week
        case .month: .month
        case .year: .year
        }
    }

    var breakdownTitle: String {
        switch self {
        case .week: "Average Day In Selected Week"
        case .month: "What Your Average Day Looked Like"
        case .year: "Your Typical Day Across The Year"
        }
    }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .week:
            calendar.mondayBased.dateInterval(of: .weekOfYear, for: date)
        case .month:
            calendar.dateInterval(of: .month, for: date)
        case .year:
            calendar.dateInterval(of: .year, for: date)
        }
    }
}

private enum InsightHistoryGrouping {
    case day
    case week
    case month

    func startDate(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: date)
        case .week:
            return calendar.mondayBased.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    func endDate(for startDate: Date, calendar: Calendar) -> Date {
        switch self {
        case .day:
            return calendar.date(byAdding: .day, value: 1, to: startDate)?.addingTimeInterval(-1) ?? startDate
        case .week:
            return calendar.mondayBased.date(byAdding: .weekOfYear, value: 1, to: startDate)?.addingTimeInterval(-1) ?? startDate
        case .month:
            return calendar.date(byAdding: .month, value: 1, to: startDate)?.addingTimeInterval(-1) ?? startDate
        }
    }

    func contains(_ date: Date, inPeriodStarting startDate: Date, calendar: Calendar) -> Bool {
        switch self {
        case .day:
            return calendar.isDate(date, inSameDayAs: startDate)
        case .week:
            guard let interval = calendar.mondayBased.dateInterval(of: .weekOfYear, for: startDate) else { return false }
            return interval.contains(date)
        case .month:
            guard let interval = calendar.dateInterval(of: .month, for: startDate) else { return false }
            return interval.contains(date)
        }
    }
}

struct WeeklyInsightsView: View {
    let segments: [ActivitySegment]
    let labelSegments: [TimelineLabelSegment]
    let calendarBoardStore: CalendarBoardStore
    var onSelectedIntervalChange: (DateInterval) async -> Void = { _ in }
    @Environment(\.productivityTextScale) private var textScale
    @Environment(\.productivityIsFullScreen) private var isFullScreen

    @State private var selectedPeriod: InsightPeriod = .week
    @State private var selectedDate = Date()

    private var selectedInterval: DateInterval? {
        selectedPeriod.interval(containing: selectedDate)
    }

    private var selectedInsightLoadKey: String {
        guard let selectedInterval else { return selectedPeriod.rawValue }
        return [
            selectedPeriod.rawValue,
            String(selectedInterval.start.timeIntervalSinceReferenceDate),
            String(selectedInterval.end.timeIntervalSinceReferenceDate)
        ].joined(separator: "|")
    }

    private var effectiveLabelSegments: [TimelineLabelSegment] {
        guard let selectedInterval else {
            return labelSegments.isEmpty
                ? TimelineLabelSegment.derived(from: segments)
                : weeklyLabelCorrectedSegments(from: segments, labelSegments: labelSegments)
        }

        let scopedSegments = activitySegmentsForDerivation(segments, around: selectedInterval)
        let scopedLabelSegments = clampedLabelSegments(labelSegments, to: selectedInterval)
        let sourceSegments = scopedLabelSegments.isEmpty
            ? TimelineLabelSegment.derived(from: scopedSegments)
            : weeklyLabelCorrectedSegments(from: scopedSegments, labelSegments: scopedLabelSegments)
        return clampedLabelSegments(sourceSegments, to: selectedInterval)
    }

    private var insightSnapshot: WeeklyInsightSnapshot {
        let effectiveLabelSegments = effectiveLabelSegments
        let breakdown = WeeklyLabelBreakdown.make(from: effectiveLabelSegments)
        let totalDuration = breakdown.reduce(0) { $0 + WeeklyLabelBreakdown.validDuration($1.duration) }
        let activeDays = Set(effectiveLabelSegments.map { Calendar.current.startOfDay(for: $0.startDate) })
        let activeDayCount = activeDays.count
        let averageDayDivisor = max(1, activeDayCount)
        let averagedBreakdown = breakdown.map { item in
            WeeklyLabelBreakdown(label: item.label, duration: item.duration / Double(averageDayDivisor))
        }
        let averageTotalDuration = averagedBreakdown.reduce(0) { $0 + WeeklyLabelBreakdown.validDuration($1.duration) }
        let excludedDate = selectedInterval?.contains(Date()) == true ? Date() : nil
        let historyItems = WeeklyHistoryItem.make(
            from: effectiveLabelSegments,
            excluding: excludedDate,
            grouping: selectedPeriod.historyGrouping
        )

        return WeeklyInsightSnapshot(
            activeDayCount: activeDayCount,
            averagedBreakdown: averagedBreakdown,
            averageTotalDuration: averageTotalDuration,
            historyItems: historyItems,
            reflectionCards: reflectionCards(
                breakdown: breakdown,
                historyItems: historyItems,
                totalDuration: totalDuration,
                activeDayCount: activeDayCount
            ),
            story: reflectionStory(
                historyItems: historyItems,
                totalDuration: totalDuration,
                productiveDuration: duration(for: .productive, in: breakdown)
            )
        )
    }

    var body: some View {
        let snapshot = insightSnapshot

        GeometryReader { proxy in
            let contentWidth = ProductivityTheme.contentWidth(for: proxy.size.width, isFullScreen: isFullScreen)
            let contentPadding = ProductivityTheme.contentPadding(for: proxy.size.width, isFullScreen: isFullScreen)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(snapshot: snapshot)
                    ReflectionSummarySection(cards: snapshot.reflectionCards)
                    WeeklyBreakdownPanel(
                        title: selectedPeriod.breakdownTitle,
                        detail: "\(snapshot.activeDayCount) active \(snapshot.activeDayCount == 1 ? "day" : "days")",
                        breakdown: snapshot.averagedBreakdown,
                        totalDuration: snapshot.averageTotalDuration
                    )
                    WeeklyHistorySection(items: snapshot.historyItems)
                    GoalInsightsPanel(
                        scope: selectedPeriod.goalInsightScope,
                        referenceDate: selectedDate,
                        calendarBoardStore: calendarBoardStore
                    )
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(contentPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(ProductivityTheme.background)
        }
        .task(id: selectedInsightLoadKey) {
            await loadSelectedInsightInterval()
        }
    }

    private func loadSelectedInsightInterval() async {
        guard let selectedInterval else { return }
        await onSelectedIntervalChange(selectedInterval)
    }

    private func header(snapshot: WeeklyInsightSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 18) {
                headerCopy(snapshot: snapshot)
                Spacer(minLength: 16)
                periodControls
            }

            VStack(alignment: .leading, spacing: 14) {
                headerCopy(snapshot: snapshot)
                periodControls
            }
        }
    }

    private func headerCopy(snapshot: WeeklyInsightSnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Insights")
                .productivityFont(.hero)
                .foregroundStyle(ProductivityTheme.textPrimary)
            ProductivityInfoHint(message: selectedPeriod.subtitle + " " + snapshot.story)
        }
    }

    private var periodControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            periodPicker

            HStack(spacing: 8) {
                Button {
                    moveSelectedPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .help("Previous \(selectedPeriod.title.lowercased())")

                Text(selectedPeriodRangeText)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .frame(minWidth: 168)

                Button {
                    moveSelectedPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveSelectedPeriodForward)
                .help("Next \(selectedPeriod.title.lowercased())")
            }
            .padding(6)
            .background(ProductivityTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var periodPicker: some View {
        Picker("Insight period", selection: $selectedPeriod) {
            ForEach(InsightPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)
    }

    private var selectedPeriodRangeText: String {
        guard let selectedInterval else { return selectedPeriod.title }
        switch selectedPeriod {
        case .week:
            return "\(WeeklyFormatters.day.string(from: selectedInterval.start)) - \(WeeklyFormatters.day.string(from: selectedInterval.end.addingTimeInterval(-1)))"
        case .month:
            return WeeklyFormatters.month.string(from: selectedInterval.start)
        case .year:
            return WeeklyFormatters.year.string(from: selectedInterval.start)
        }
    }

    private var canMoveSelectedPeriodForward: Bool {
        guard let selectedInterval,
              let currentInterval = selectedPeriod.interval(containing: Date()) else {
            return false
        }

        return selectedInterval.start < currentInterval.start
    }

    private func moveSelectedPeriod(by value: Int) {
        let component: Calendar.Component = switch selectedPeriod {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }

        guard let newDate = Calendar.current.date(byAdding: component, value: value, to: selectedDate) else { return }
        let today = Date()
        if value > 0,
           let newInterval = selectedPeriod.interval(containing: newDate),
           let currentInterval = selectedPeriod.interval(containing: today),
           newInterval.start > currentInterval.start {
            selectedDate = today
        } else {
            selectedDate = newDate
        }
    }

    private func reflectionCards(
        breakdown: [WeeklyLabelBreakdown],
        historyItems: [WeeklyHistoryItem],
        totalDuration: TimeInterval,
        activeDayCount: Int
    ) -> [ReflectionCard] {
        let averageDayDivisor = max(1, activeDayCount)
        let productiveTime = duration(for: .productive, in: breakdown)
        let unproductiveTime = duration(for: .unproductive, in: breakdown)
        let productiveRatio = totalDuration.isFinite && totalDuration > 0 ? Int(min(max(productiveTime / totalDuration, 0), 1) * 100) : 0
        let averageProductiveTime = productiveTime / Double(averageDayDivisor)
        let averageUnproductiveTime = unproductiveTime / Double(averageDayDivisor)
        let bestPeriod = historyItems.max { lhs, rhs in
            if lhs.productiveRatio == rhs.productiveRatio {
                return lhs.productiveDuration < rhs.productiveDuration
            }
            return lhs.productiveRatio < rhs.productiveRatio
        }
        let biggestDrift = historyItems.max { $0.unproductiveDuration < $1.unproductiveDuration }
        let consistencyCount = historyItems.filter { $0.productiveRatio >= 0.60 }.count

        return [
            ReflectionCard(
                title: "Focus Ratio",
                value: "\(productiveRatio)%",
                detail: "Share of time spent focused",
                accent: .focus
            ),
            ReflectionCard(
                title: "Average Focus",
                value: DurationFormatting.abbreviated(averageProductiveTime),
                detail: "What a typical focused day looked like",
                accent: .focus
            ),
            ReflectionCard(
                title: "Best Period",
                value: bestPeriod.map(\.dateRangeText) ?? "No data",
                detail: bestPeriod.map { "\($0.productivePercentage)% focused" } ?? "Complete a period to reveal it",
                accent: .research
            ),
            ReflectionCard(
                title: "Biggest Drift",
                value: DurationFormatting.abbreviated(biggestDrift?.unproductiveDuration ?? averageUnproductiveTime),
                detail: biggestDrift.map { "Most drift happened in \($0.dateRangeText)" } ?? "Average drift per active day",
                accent: .entertainment
            ),
            ReflectionCard(
                title: "Consistency",
                value: historyItems.isEmpty ? "0/0" : "\(consistencyCount)/\(historyItems.count)",
                detail: "Periods above 60% focus",
                accent: .focus
            )
        ]
    }

    private func reflectionStory(
        historyItems: [WeeklyHistoryItem],
        totalDuration: TimeInterval,
        productiveDuration: TimeInterval
    ) -> String {
        guard totalDuration > 0 else {
            return "No pattern yet. Capture a few periods and this page will turn into a clearer story."
        }

        let productiveRatio = Int(min(max(productiveDuration / totalDuration, 0), 1) * 100)
        let bestPeriod = historyItems.max { lhs, rhs in
            if lhs.productiveRatio == rhs.productiveRatio {
                return lhs.productiveDuration < rhs.productiveDuration
            }
            return lhs.productiveRatio < rhs.productiveRatio
        }
        let biggestDrift = historyItems.max { $0.unproductiveDuration < $1.unproductiveDuration }

        if let bestPeriod, let biggestDrift, biggestDrift.unproductiveDuration > 0 {
            return "You protected focus for \(productiveRatio)% of this period. Your strongest stretch was \(bestPeriod.dateRangeText), while most drift showed up in \(biggestDrift.dateRangeText)."
        }

        if let bestPeriod {
            return "You protected focus for \(productiveRatio)% of this period. Your clearest stretch was \(bestPeriod.dateRangeText)."
        }

        return "You protected focus for \(productiveRatio)% of this period."
    }

    private func duration(for label: ActivityLabel, in breakdown: [WeeklyLabelBreakdown]) -> TimeInterval {
        ActivityLabel.rollupDuration(for: label, in: breakdown.map { ($0.label, $0.duration) })
    }

    private func activitySegmentsForDerivation(_ segments: [ActivitySegment], around interval: DateInterval) -> [ActivitySegment] {
        var previousSegment: ActivitySegment?
        var nextSegment: ActivitySegment?
        var scopedSegments: [ActivitySegment] = []

        for segment in segments {
            guard let segmentInterval = segment.safeInterval else { continue }
            if interval.intersects(segmentInterval) {
                scopedSegments.append(segment)
            } else if segment.endDate <= interval.start {
                if previousSegment == nil || segment.endDate > (previousSegment?.endDate ?? .distantPast) {
                    previousSegment = segment
                }
            } else if segment.startDate >= interval.end,
                      nextSegment == nil || segment.startDate < (nextSegment?.startDate ?? .distantFuture) {
                nextSegment = segment
            }
        }

        return ([previousSegment].compactMap { $0 } + scopedSegments + [nextSegment].compactMap { $0 })
            .sorted {
                if $0.startDate == $1.startDate {
                    return $0.endDate < $1.endDate
                }

                return $0.startDate < $1.startDate
            }
    }

    private func clampedLabelSegments(_ segments: [TimelineLabelSegment], to interval: DateInterval) -> [TimelineLabelSegment] {
        segments.compactMap { segment in
            guard segment.endDate > segment.startDate else { return nil }
            let segmentInterval = DateInterval(start: segment.startDate, end: segment.endDate)
            guard interval.intersects(segmentInterval) else { return nil }
            let startDate = max(segment.startDate, interval.start)
            let endDate = min(segment.endDate, interval.end)
            guard endDate > startDate else { return nil }
            return TimelineLabelSegment(id: segment.id, label: segment.label, startDate: startDate, endDate: endDate)
        }
    }

}

func weeklyLabelCorrectedSegments(
    from segments: [ActivitySegment],
    labelSegments: [TimelineLabelSegment]
) -> [TimelineLabelSegment] {
    let derivedSegments = TimelineLabelSegment.derived(from: segments)
    let normalizedLabelSegments = TimelineLabelSegment.normalized(labelSegments)
    guard !normalizedLabelSegments.isEmpty else { return derivedSegments }

    let activityBoundLabelSegments = weeklyLabelSegmentsClippedToDerivedActivity(
        normalizedLabelSegments,
        derivedSegments: derivedSegments
    )
    let editedIntervals = activityBoundLabelSegments.map { DateInterval(start: $0.startDate, end: $0.endDate) }
    let remainingDerivedSegments = derivedSegments.flatMap { segment in
        weeklyLabelSegmentsBySubtracting(editedIntervals, from: segment)
    }

    return TimelineLabelSegment.normalized(remainingDerivedSegments + activityBoundLabelSegments)
}

private func weeklyLabelSegmentsClippedToDerivedActivity(
    _ labelSegments: [TimelineLabelSegment],
    derivedSegments: [TimelineLabelSegment]
) -> [TimelineLabelSegment] {
    let derivedIntervals = derivedSegments.map { DateInterval(start: $0.startDate, end: $0.endDate) }

    return TimelineLabelSegment.normalized(labelSegments.flatMap { labelSegment in
        derivedIntervals.compactMap { derivedInterval in
            guard derivedInterval.intersects(DateInterval(start: labelSegment.startDate, end: labelSegment.endDate)) else {
                return nil
            }
            let startDate = max(labelSegment.startDate, derivedInterval.start)
            let endDate = min(labelSegment.endDate, derivedInterval.end)
            guard endDate > startDate else { return nil }
            return TimelineLabelSegment(
                id: labelSegment.id,
                label: labelSegment.label,
                startDate: startDate,
                endDate: endDate
            )
        }
    })
}

private func weeklyLabelSegmentsBySubtracting(
    _ excludedIntervals: [DateInterval],
    from segment: TimelineLabelSegment
) -> [TimelineLabelSegment] {
    var remainingIntervals = [DateInterval(start: segment.startDate, end: segment.endDate)]

    for excludedInterval in excludedIntervals {
        remainingIntervals = remainingIntervals.flatMap { weeklyDateIntervalsBySubtracting(excludedInterval, from: $0) }
        guard !remainingIntervals.isEmpty else { break }
    }

    return remainingIntervals.compactMap { interval in
        guard interval.duration > 0 else { return nil }
        return TimelineLabelSegment(
            id: interval.start == segment.startDate && interval.end == segment.endDate ? segment.id : UUID(),
            label: segment.label,
            startDate: interval.start,
            endDate: interval.end
        )
    }
}

private func weeklyDateIntervalsBySubtracting(_ excludedInterval: DateInterval, from interval: DateInterval) -> [DateInterval] {
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

private struct WeeklyInsightSnapshot {
    let activeDayCount: Int
    let averagedBreakdown: [WeeklyLabelBreakdown]
    let averageTotalDuration: TimeInterval
    let historyItems: [WeeklyHistoryItem]
    let reflectionCards: [ReflectionCard]
    let story: String
}

private struct ReflectionCard: Identifiable {
    var id: String { title }
    let title: String
    let value: String
    let detail: String
    let accent: ActivityCategory
}

private struct ReflectionSummarySection: View {
    let cards: [ReflectionCard]

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12, alignment: .top)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(cards) { card in
                ReflectionCardView(card: card)
            }
        }
    }
}

private struct ReflectionCardView: View {
    let card: ReflectionCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(card.accent.tint.opacity(0.88))
                    .frame(width: 10, height: 10)
                Text(card.title)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Text(card.value)
                .productivityFont(.metricProminent)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(card.detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .lineLimit(2)
                .help(card.detail)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .padding(14)
        .background(ProductivityTheme.elevatedBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(card.accent.tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct WeeklyBreakdownPanel: View {
    let title: String
    let detail: String
    let breakdown: [WeeklyLabelBreakdown]
    let totalDuration: TimeInterval

    private let visibleLimit = 4

    @State private var showsAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(title, systemImage: "chart.pie")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Spacer()
                Text(detail)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .help(detail)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    WeeklyPieChartView(breakdown: breakdown, totalDuration: totalDuration)
                        .frame(width: 260, height: 260)
                        .frame(maxWidth: .infinity)

                    breakdownRows
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(spacing: 18) {
                    WeeklyPieChartView(breakdown: breakdown, totalDuration: totalDuration)
                        .frame(width: 220, height: 220)

                    breakdownRows
                }
            }
        }
        .weeklyPanelStyle()
    }

    private var visibleBreakdown: [WeeklyLabelBreakdown] {
        showsAll ? breakdown : Array(breakdown.prefix(visibleLimit))
    }

    private var breakdownRows: some View {
        VStack(spacing: 10) {
            ForEach(visibleBreakdown) { item in
                WeeklyBreakdownRow(item: item, totalDuration: totalDuration)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if breakdown.count > visibleLimit {
                Button {
                    withAnimation(.smooth(duration: 0.22)) {
                        showsAll.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(showsAll ? "Show Less" : "View All \(breakdown.count) Labels")
                            .productivityFont(.bodyStrong)
                        Image(systemName: showsAll ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(ProductivityTheme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeeklyPieChartView: View {
    let breakdown: [WeeklyLabelBreakdown]
    let totalDuration: TimeInterval

    private var productivePercentage: Int {
        guard totalDuration.isFinite, totalDuration > 0 else { return 0 }
        let productiveDuration = ActivityLabel.rollupDuration(for: .productive, in: breakdown.map { ($0.label, $0.duration) })
        let ratio = min(max(productiveDuration / totalDuration, 0), 1)
        return Int(ratio * 100)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(ProductivityTheme.subtleBackground.opacity(0.66))
                .overlay(
                    Circle()
                        .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: ProductivityTheme.accent.opacity(0.14), radius: 26, y: 16)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ProductivityTheme.elevatedBackground.opacity(0.0),
                            ProductivityTheme.elevatedBackground.opacity(0.42)
                        ],
                        center: .center,
                        startRadius: 18,
                        endRadius: 132
                    )
                )
                .padding(10)

            Chart(breakdown) { item in
                SectorMark(
                    angle: .value("Duration", chartDuration(for: item)),
                    innerRadius: .ratio(0.58),
                    angularInset: 1.2
                )
                .cornerRadius(5)
                .foregroundStyle(item.label.tint.opacity(item.duration > 0 ? 0.86 : 0.20))
            }
            .chartLegend(.hidden)
            .chartBackground { _ in
                Circle()
                    .fill(ProductivityTheme.elevatedBackground.opacity(0.92))
                    .overlay(
                        Circle()
                            .stroke(ProductivityTheme.border.opacity(0.38), lineWidth: 1)
                    )
            }
            .padding(18)

            VStack(spacing: 4) {
                Text("\(productivePercentage)%")
                    .font(ProductivityTypography.font(.metricHero, scale: 1, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .contentTransition(.numericText())
                Text("productive")
                    .productivityFont(.bodyMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }
        }
        .animation(.smooth(duration: 0.32), value: breakdown.map { WeeklyLabelBreakdown.validDuration($0.duration) })
        .aspectRatio(1, contentMode: .fit)
    }

    private func chartDuration(for item: WeeklyLabelBreakdown) -> TimeInterval {
        let duration = WeeklyLabelBreakdown.validDuration(item.duration)
        if duration > 0 {
            return duration
        }

        return totalDuration > 0 ? 0 : 1
    }
}

private struct WeeklyHistorySection: View {
    let items: [WeeklyHistoryItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Pattern History", systemImage: "clock.arrow.circlepath")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Spacer()
                Text("\(items.count) periods")
                    .productivityFont(.bodyMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Text("Scan for the strongest and weakest periods before you dive into the full ledger.")
                .productivityFont(.body)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .help("Review your strongest and weakest periods before opening the full history.")

            VStack(spacing: 10) {
                if items.isEmpty {
                    EmptyWeeklyHistoryView()
                } else {
                    ForEach(items) { item in
                        WeeklyHistoryRow(item: item)
                    }
                }
            }
        }
        .weeklyPanelStyle()
    }
}

private struct EmptyWeeklyHistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No history yet")
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text("Completed periods will appear here after activity has been captured.")
                .productivityFont(.body)
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.subtleBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WeeklyHistoryRow: View {
    let item: WeeklyHistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    rowHeader
                    Spacer(minLength: 12)
                    rowMetrics
                }

                VStack(alignment: .leading, spacing: 8) {
                    rowHeader
                    rowMetrics
                }
            }

            WeeklyProgressBar(
                productiveRatio: item.productiveRatio,
                unproductiveRatio: item.unproductiveRatio,
                unknownRatio: item.unknownRatio
            )
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var rowHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.dateRangeText)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text("\(item.productivePercentage)% productive")
                .font(ProductivityTypography.font(.bodyMonospaced, weight: .medium))
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
    }

    private var rowMetrics: some View {
        HStack(spacing: 10) {
            HistoryMetricPill(label: "Productive", value: DurationFormatting.abbreviated(item.productiveDuration), tint: ActivityLabel.productive.tint)
            HistoryMetricPill(label: "Drift", value: DurationFormatting.abbreviated(item.unproductiveDuration), tint: ActivityLabel.unproductive.tint)
            HistoryMetricPill(label: "Unclear", value: DurationFormatting.abbreviated(item.unknownDuration), tint: ActivityLabel.unknown.tint)
        }
    }
}

private struct WeeklyProgressBar: View {
    let productiveRatio: Double
    let unproductiveRatio: Double
    let unknownRatio: Double

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
            let productiveWidth = availableWidth * sanitizedRatio(productiveRatio)
            let unproductiveWidth = availableWidth * sanitizedRatio(unproductiveRatio)
            let unknownWidth = availableWidth * sanitizedRatio(unknownRatio)

            HStack(spacing: 0) {
                ActivityLabel.productive.tint.opacity(0.78)
                    .frame(width: productiveWidth)
                ActivityLabel.unproductive.tint.opacity(0.45)
                    .frame(width: unproductiveWidth)
                ActivityLabel.unknown.tint.opacity(0.30)
                    .frame(width: unknownWidth)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 10)
        .background(ActivityLabel.unknown.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(ProductivityTheme.border.opacity(0.35), lineWidth: 1)
        )
        .animation(.smooth(duration: 0.34), value: sanitizedRatio(productiveRatio))
        .animation(.smooth(duration: 0.34), value: sanitizedRatio(unproductiveRatio))
        .animation(.smooth(duration: 0.34), value: sanitizedRatio(unknownRatio))
    }

    private func sanitizedRatio(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 0 }
        return min(max(ratio, 0), 1)
    }
}

private struct HistoryMetricPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
            Text(value)
                .font(ProductivityTypography.font(.bodyMonospaced, weight: .medium))
            Text(label)
                .productivityFont(.bodyMedium)
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
        .foregroundStyle(ProductivityTheme.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension View {
    func weeklyPanelStyle() -> some View {
        self
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
    }
}

private struct WeeklyBreakdownRow: View {
    let item: WeeklyLabelBreakdown
    let totalDuration: TimeInterval

    private var percentage: Int {
        guard totalDuration.isFinite, totalDuration > 0 else { return 0 }
        let ratio = WeeklyLabelBreakdown.validDuration(item.duration) / totalDuration
        return Int(min(max(ratio, 0), 1) * 100)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(item.label.tint.opacity(0.14))
                RoundedRectangle(cornerRadius: 7)
                    .stroke(item.label.tint.opacity(0.34), lineWidth: 1)
                Circle()
                    .fill(item.label.tint.opacity(0.88))
                    .frame(width: 8, height: 8)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: item.label))
                    .productivityFont(.bodyMedium)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text(DurationFormatting.abbreviated(item.duration))
                    .productivityFont(.bodyMonospaced)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Spacer()

            Text("\(percentage)%")
                .font(ProductivityTypography.font(.bodyMonospaced, weight: .semibold))
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(item.label.tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func title(for label: ActivityLabel) -> String {
        switch label.commonRollup {
        case .productive:
            label == .productive ? "Focused" : label.title
        case .unproductive:
            label == .unproductive ? "Drift" : label.title
        case .unknown:
            label == .unknown ? "Unclear" : label.title
        default:
            label.title
        }
    }
}

private struct WeeklyLabelBreakdown: Identifiable {
    let label: ActivityLabel
    let duration: TimeInterval

    var id: ActivityLabel { label }

    static func make(from segments: [ActivitySegment]) -> [WeeklyLabelBreakdown] {
        let groupedDurations = Dictionary(grouping: segments, by: \.label)
            .mapValues { segments in
                segments.reduce(0) { $0 + validDuration($1.duration) }
            }

        let labels = ActivityLabel.allCases + groupedDurations.keys.filter { !ActivityLabel.allCases.contains($0) }
        return labels.map { label in
            WeeklyLabelBreakdown(label: label, duration: groupedDurations[label] ?? 0)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func make(from labelSegments: [TimelineLabelSegment]) -> [WeeklyLabelBreakdown] {
        let groupedDurations = Dictionary(grouping: labelSegments, by: \.label)
            .mapValues { segments in
                segments.reduce(0) { $0 + validDuration($1.duration) }
            }

        let labels = ActivityLabel.allCases + groupedDurations.keys.filter { !ActivityLabel.allCases.contains($0) }
        return labels.map { label in
            WeeklyLabelBreakdown(label: label, duration: groupedDurations[label] ?? 0)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func validDuration(_ duration: TimeInterval) -> TimeInterval {
        guard duration.isFinite, duration > 0 else { return 0 }
        return duration
    }
}

private struct WeeklyHistoryItem: Identifiable {
    var id: TimeInterval { startDate.timeIntervalSinceReferenceDate }
    let startDate: Date
    let endDate: Date
    let productiveDuration: TimeInterval
    let unproductiveDuration: TimeInterval
    let unknownDuration: TimeInterval

    var totalDuration: TimeInterval {
        WeeklyLabelBreakdown.validDuration(productiveDuration)
            + WeeklyLabelBreakdown.validDuration(unproductiveDuration)
            + WeeklyLabelBreakdown.validDuration(unknownDuration)
    }

    var productiveRatio: Double {
        ratio(for: productiveDuration)
    }

    var unproductiveRatio: Double {
        ratio(for: unproductiveDuration)
    }

    var unknownRatio: Double {
        ratio(for: unknownDuration)
    }

    var productivePercentage: Int {
        Int(productiveRatio * 100)
    }

    private func ratio(for duration: TimeInterval) -> Double {
        guard totalDuration.isFinite, totalDuration > 0 else { return 0 }
        return min(max(WeeklyLabelBreakdown.validDuration(duration) / totalDuration, 0), 1)
    }

    var dateRangeText: String {
        let calendar = Calendar.current
        if calendar.component(.day, from: startDate) == 1,
           calendar.component(.day, from: endDate.addingTimeInterval(1)) == 1,
           !calendar.isDate(startDate, inSameDayAs: endDate) {
            return WeeklyFormatters.month.string(from: startDate)
        }

        if calendar.isDate(startDate, inSameDayAs: endDate) {
            return WeeklyFormatters.day.string(from: startDate)
        }

        return "\(WeeklyFormatters.day.string(from: startDate)) - \(WeeklyFormatters.day.string(from: endDate))"
    }

    static func make(
        from segments: [ActivitySegment],
        excluding excludedDate: Date? = nil,
        grouping: InsightHistoryGrouping = .day
    ) -> [WeeklyHistoryItem] {
        let calendar = Calendar.current
        let groupedSegments = Dictionary(grouping: segments) { segment in
            grouping.startDate(for: segment.startDate, calendar: calendar)
        }

        return groupedSegments.keys.sorted().filter { periodStart in
            guard let excludedDate else { return true }
            return !grouping.contains(excludedDate, inPeriodStarting: periodStart, calendar: calendar)
        }.map { periodStart in
            let periodSegments = groupedSegments[periodStart, default: []]
            return makeItem(for: periodStart, grouping: grouping, segments: periodSegments)
        }
    }

    static func make(
        from labelSegments: [TimelineLabelSegment],
        excluding excludedDate: Date? = nil,
        grouping: InsightHistoryGrouping = .day
    ) -> [WeeklyHistoryItem] {
        let calendar = Calendar.current
        let groupedSegments = Dictionary(grouping: labelSegments) { segment in
            grouping.startDate(for: segment.startDate, calendar: calendar)
        }

        return groupedSegments.keys.sorted().filter { periodStart in
            guard let excludedDate else { return true }
            return !grouping.contains(excludedDate, inPeriodStarting: periodStart, calendar: calendar)
        }.map { periodStart in
            let periodSegments = groupedSegments[periodStart, default: []]
            return makeItem(for: periodStart, grouping: grouping, labelSegments: periodSegments)
        }
    }

    private static func makeItem(
        for periodStart: Date,
        grouping: InsightHistoryGrouping,
        segments: [ActivitySegment]
    ) -> WeeklyHistoryItem {
        let calendar = Calendar.current
        let periodEnd = grouping.endDate(for: periodStart, calendar: calendar)
        let productiveDuration = duration(for: .productive, in: segments)
        let unproductiveDuration = duration(for: .unproductive, in: segments)
        let unknownDuration = duration(for: .unknown, in: segments)

        return WeeklyHistoryItem(
            startDate: periodStart,
            endDate: periodEnd,
            productiveDuration: productiveDuration,
            unproductiveDuration: unproductiveDuration,
            unknownDuration: unknownDuration
        )
    }

    private static func makeItem(
        for periodStart: Date,
        grouping: InsightHistoryGrouping,
        labelSegments: [TimelineLabelSegment]
    ) -> WeeklyHistoryItem {
        let calendar = Calendar.current
        let periodEnd = grouping.endDate(for: periodStart, calendar: calendar)
        let productiveDuration = duration(for: .productive, in: labelSegments)
        let unproductiveDuration = duration(for: .unproductive, in: labelSegments)
        let unknownDuration = duration(for: .unknown, in: labelSegments)

        return WeeklyHistoryItem(
            startDate: periodStart,
            endDate: periodEnd,
            productiveDuration: productiveDuration,
            unproductiveDuration: unproductiveDuration,
            unknownDuration: unknownDuration
        )
    }

    private static func duration(for label: ActivityLabel, in segments: [ActivitySegment]) -> TimeInterval {
        segments
            .filter { $0.label.commonRollup == label }
            .reduce(0) { $0 + WeeklyLabelBreakdown.validDuration($1.duration) }
    }

    private static func duration(for label: ActivityLabel, in segments: [TimelineLabelSegment]) -> TimeInterval {
        segments
            .filter { $0.label.commonRollup == label }
            .reduce(0) { $0 + WeeklyLabelBreakdown.validDuration($1.duration) }
    }

}

private enum WeeklyFormatters {
    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let year: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        return formatter
    }()
}

#if DEBUG
#Preview {
    WeeklyInsightsView(
        segments: ActivitySegment.sampleHistory,
        labelSegments: [],
        calendarBoardStore: CalendarBoardStore(
            storeURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ProductivityWeeklyInsightsPreview", isDirectory: false)
                .appendingPathExtension("calendarboard")
        )
    )
        .frame(width: 1100, height: 760)
        .preferredColorScheme(.dark)
}
#endif
