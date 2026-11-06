import Charts
import SwiftUI

struct AnalyticsView: View {
    let segments: [ActivitySegment]
    @Environment(\.productivityIsFullScreen) private var isFullScreen

    @State private var selectedRange: AnalyticsRange = .last30Days
    @State private var hourlyChartStyle: HourlyChartStyle = .both
    @State private var snapshot: AnalyticsSnapshot

    private let engine = AdvancedAnalyticsEngine()

    init(segments: [ActivitySegment]) {
        self.segments = segments
        _snapshot = State(initialValue: engine.snapshot(from: segments, range: .last30Days))
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = ProductivityTheme.contentWidth(for: proxy.size.width, isFullScreen: isFullScreen)
            let contentPadding = ProductivityTheme.contentPadding(for: proxy.size.width, isFullScreen: isFullScreen)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(snapshot: snapshot)
                    summaryGrid(snapshot: snapshot)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            dailyTrendPanel(snapshot: snapshot)
                            hourlyProfilePanel(snapshot: snapshot)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            dailyTrendPanel(snapshot: snapshot)
                            hourlyProfilePanel(snapshot: snapshot)
                        }
                    }
                    categoryBreakdownPanel(snapshot: snapshot)
                    topAppsPanel(snapshot: snapshot)
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(contentPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(ProductivityTheme.background)
        }
        .onChange(of: selectedRange) { _, _ in
            refreshSnapshot()
        }
        .onChange(of: segments) { _, _ in
            refreshSnapshot()
        }
    }

    private func refreshSnapshot() {
        snapshot = engine.snapshot(from: segments, range: selectedRange)
    }

    private func header(snapshot: AnalyticsSnapshot) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                headerCopy(snapshot: snapshot)
                Spacer(minLength: 16)
                rangePicker
            }

            VStack(alignment: .leading, spacing: 14) {
                headerCopy(snapshot: snapshot)
                rangePicker
            }
        }
    }

    private func headerCopy(snapshot: AnalyticsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Analytics")
                .productivityFont(.hero)
                .foregroundStyle(ProductivityTheme.textPrimary)
            ProductivityInfoHint(message: "Patterns from captured activity. " + snapshotStory(snapshot: snapshot))
        }
    }

    private var rangePicker: some View {
        Picker("Analytics range", selection: $selectedRange) {
            ForEach(AnalyticsRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
    }

    private func summaryGrid(snapshot: AnalyticsSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 230), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            AnalyticsStatCard(
                title: "Focus Ratio",
                value: percentage(snapshot.productiveRatio),
                detail: "\(snapshot.activeDayCount) active days in range",
                accent: .focus
            )
            AnalyticsStatCard(
                title: "Avg Focus Streak",
                value: DurationFormatting.abbreviated(snapshot.averageFocusStreak),
                detail: "Mean uninterrupted productive run",
                accent: .research
            )
            AnalyticsStatCard(
                title: "Switch Load",
                value: String(format: "%.1f/h", snapshot.contextSwitchesPerHour),
                detail: "\(snapshot.contextSwitchCount) context switches",
                accent: .communication
            )
            AnalyticsStatCard(
                title: "Recovery Lag",
                value: DurationFormatting.abbreviated(snapshot.medianRecoveryTime),
                detail: "Median time back to productive work",
                accent: .entertainment
            )
        }
    }

    private func dailyTrendPanel(snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader(
                title: "Daily Time Breakdown",
                detail: "Productive hours (teal) and other tracked time stacked by day — bar height shows total effort, teal portion shows quality"
            )

            Chart {
                ForEach(snapshot.dailyItems) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Hours", item.productiveDuration / 3600)
                    )
                    .foregroundStyle(by: .value("Type", "Productive"))
                }
                ForEach(snapshot.dailyItems) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("Hours", max(0, item.trackedDuration - item.productiveDuration) / 3600)
                    )
                    .foregroundStyle(by: .value("Type", "Other"))
                }
            }
            .chartForegroundStyleScale([
                "Productive": ProductivityTheme.accent.opacity(0.82),
                "Other": ProductivityTheme.textSecondary.opacity(0.22)
            ])
            .chartLegend(.hidden)
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(ProductivityTheme.border.opacity(0.35))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text(hours >= 1 ? "\(Int(hours))h" : "\(Int(hours * 60))m")
                                .font(ProductivityTypography.font(.caption))
                        }
                    }
                    .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(ProductivityTheme.border.opacity(0.2))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(ProductivityTypography.font(.caption))
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
            .frame(minHeight: 240)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .analyticsPanelStyle()
    }

    private func hourlyProfilePanel(snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    panelHeader(
                        title: "Hourly Focus Profile",
                        detail: "Best and weakest hours across the selected range"
                    )
                    Spacer(minLength: 16)
                    hourlyChartStylePicker(alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 12) {
                    panelHeader(
                        title: "Hourly Focus Profile",
                        detail: "Best and weakest hours across the selected range"
                    )
                    hourlyChartStylePicker(alignment: .leading)
                }
            }

            Chart {
                if hourlyChartStyle.showsBars {
                    ForEach(snapshot.hourlyItems) { item in
                        BarMark(
                            x: .value("Hour", item.hour),
                            y: .value("Focus Ratio", item.productiveRatio)
                        )
                        .foregroundStyle(item.barColor.opacity(hourlyChartStyle == .both ? 0.4 : 0.82))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                if hourlyChartStyle.showsLine {
                    ForEach(snapshot.hourlyItems) { item in
                        AreaMark(
                            x: .value("Hour", item.hour),
                            y: .value("Focus Ratio", item.productiveRatio)
                        )
                        .foregroundStyle(ProductivityTheme.accent.opacity(hourlyChartStyle == .both ? 0.12 : 0.16))
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(snapshot.hourlyItems) { item in
                        LineMark(
                            x: .value("Hour", item.hour),
                            y: .value("Focus Ratio", item.productiveRatio)
                        )
                        .foregroundStyle(ProductivityTheme.accent)
                        .lineStyle(.init(lineWidth: hourlyChartStyle == .both ? 2.6 : 3.0, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Hour", item.hour),
                            y: .value("Focus Ratio", item.productiveRatio)
                        )
                        .foregroundStyle(ProductivityTheme.accent)
                        .symbolSize(hourlyChartStyle == .line ? 40 : 26)
                    }
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 0.25, 0.5, 0.75, 1.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(ProductivityTheme.border.opacity(0.35))
                    AxisValueLabel {
                        if let ratio = value.as(Double.self) {
                            Text("\(Int(ratio * 100))%")
                                .font(ProductivityTypography.font(.caption))
                        }
                    }
                    .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0, 4, 8, 12, 16, 20]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.8))
                        .foregroundStyle(ProductivityTheme.border.opacity(0.2))
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text(hourLabel(for: hour))
                                .font(ProductivityTypography.font(.caption))
                        }
                    }
                    .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
            .frame(minHeight: 240)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: 12, alignment: .top)],
                alignment: .leading,
                spacing: 12
            ) {
                hourBadge(
                    title: "Peak Window",
                    value: snapshot.peakFocusHour.map(\.hourRangeLabel) ?? "Not enough data",
                    detail: snapshot.peakFocusHour.map { percentage($0.productiveRatio) + " focused" } ?? "Need at least 20 minutes tracked"
                )
                hourBadge(
                    title: "Weakest Window",
                    value: snapshot.weakestFocusHour.map(\.hourRangeLabel) ?? "Not enough data",
                    detail: snapshot.weakestFocusHour.map { percentage($0.productiveRatio) + " focused" } ?? "Need at least 20 minutes tracked"
                )
            }

        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .analyticsPanelStyle()
    }

    private func categoryBreakdownPanel(snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader(
                title: "Time by Label",
                detail: "How tracked time distributes across activity labels in the selected range"
            )

            let items = categoryBreakdownItems(from: snapshot)

            if items.isEmpty {
                Text("No activity tracked in this range.")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .padding(.vertical, 8)
            } else {
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        ForEach(items) { item in
                            let ratio = snapshot.totalTrackedTime > 0 ? item.duration / snapshot.totalTrackedTime : 0
                            if ratio > 0.01 {
                                Rectangle()
                                    .fill(item.label.tint.opacity(0.85))
                                    .frame(width: geo.size.width * ratio)
                            }
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 170, maximum: 280), spacing: 8, alignment: .top)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        categoryLegendRow(item: item, totalTrackedTime: snapshot.totalTrackedTime)
                    }
                }

                Divider()
                    .background(ProductivityTheme.border.opacity(0.3))

                HStack(spacing: 20) {
                    diagnosticInlineStat(
                        title: "Best streak",
                        value: DurationFormatting.abbreviated(snapshot.longestFocusStreak)
                    )
                    diagnosticInlineStat(
                        title: "Total tracked",
                        value: DurationFormatting.abbreviated(snapshot.totalTrackedTime)
                    )
                    diagnosticInlineStat(
                        title: "Productive",
                        value: DurationFormatting.abbreviated(snapshot.productiveTime)
                    )
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .analyticsPanelStyle()
    }

    private func categoryBreakdownItems(from snapshot: AnalyticsSnapshot) -> [CategoryBreakdownItem] {
        let allCases = ActivityLabel.allCases
        return (allCases + snapshot.labelBreakdown.keys.filter { !allCases.contains($0) })
            .compactMap { label -> CategoryBreakdownItem? in
                guard let duration = snapshot.labelBreakdown[label], duration > 0 else { return nil }
                return CategoryBreakdownItem(label: label, duration: duration)
            }
            .sorted { $0.duration > $1.duration }
    }

    private func categoryLegendRow(item: CategoryBreakdownItem, totalTrackedTime: TimeInterval) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(item.label.tint.opacity(0.88))
                .frame(width: 10, height: 10)
            Text(item.label.title)
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(DurationFormatting.abbreviated(item.duration))
                    .productivityFont(.captionMonospaced)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                if totalTrackedTime > 0 {
                    Text(percentage(item.duration / totalTrackedTime))
                        .productivityFont(.note)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ProductivityTheme.subtleBackground.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func diagnosticInlineStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .productivityFont(.note)
                .foregroundStyle(ProductivityTheme.textSecondary)
            Text(value)
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
        }
    }

    private func topAppsPanel(snapshot: AnalyticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            panelHeader(
                title: "Top Apps",
                detail: "Bar shows time relative to the top app; teal fill shows the productive fraction"
            )

            let maxDuration = snapshot.topApps.map(\.trackedDuration).max() ?? 1

            VStack(spacing: 10) {
                ForEach(snapshot.topApps) { app in
                    topAppRow(app, maxDuration: maxDuration)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .analyticsPanelStyle()
    }

    private func topAppRow(_ app: AnalyticsAppItem, maxDuration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(app.appName)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: 8)

                Text(DurationFormatting.abbreviated(app.trackedDuration))
                    .productivityFont(.captionMonospaced)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Text("·")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)

                Text("\(percentage(app.productiveRatio)) focus")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(app.productiveRatio >= 0.5 ? ProductivityTheme.accent : ActivityCategory.entertainment.tint)
            }

            GeometryReader { geo in
                let trackWidth = maxDuration > 0 ? geo.size.width * (app.trackedDuration / maxDuration) : 0
                let focusWidth = trackWidth * app.productiveRatio

                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(ProductivityTheme.border.opacity(0.22))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Rectangle()
                        .fill(ProductivityTheme.textSecondary.opacity(0.2))
                        .frame(width: trackWidth)

                    Rectangle()
                        .fill(app.productiveRatio >= 0.5 ? ProductivityTheme.accent.opacity(0.8) : ActivityCategory.entertainment.tint.opacity(0.75))
                        .frame(width: max(0, focusWidth))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .padding(14)
        .background(ProductivityTheme.subtleBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(ProductivityTheme.border.opacity(0.28), lineWidth: 1)
        )
        .help(app.bundleIdentifier)
    }

    private func snapshotStory(snapshot: AnalyticsSnapshot) -> String {
        let peakText = snapshot.peakFocusHour.map(\.hourRangeLabel) ?? "no stable peak yet"
        let weakText = snapshot.weakestFocusHour.map(\.hourRangeLabel) ?? "no weak window yet"
        return "Your strongest observed window is \(peakText), while attention tends to soften around \(weakText). Switch load sits at \(String(format: "%.1f", snapshot.contextSwitchesPerHour)) per tracked hour."
    }

    private func panelHeader(title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(title)
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)
            ProductivityInfoHint(message: detail)
        }
    }

    @ViewBuilder
    private func hourlyChartStylePicker(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 10) {
            Text("Chart style")
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textSecondary)

            Picker("Hourly chart style", selection: $hourlyChartStyle) {
                ForEach(HourlyChartStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220)
        }
    }

    private func hourBadge(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textSecondary)
            Text(value)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text(detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .lineLimit(2)
                .help(detail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.52), in: RoundedRectangle(cornerRadius: 10))
    }

    private func percentage(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }

    private func hourLabel(for hour: Int) -> String {
        switch hour {
        case 0:
            "12a"
        case 12:
            "12p"
        case 13...23:
            "\(hour - 12)p"
        default:
            "\(hour)a"
        }
    }
}

private enum HourlyChartStyle: String, CaseIterable, Identifiable {
    case line
    case bars
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:
            "Line"
        case .bars:
            "Bars"
        case .both:
            "Both"
        }
    }

    var showsLine: Bool {
        self == .line || self == .both
    }

    var showsBars: Bool {
        self == .bars || self == .both
    }
}

private struct AnalyticsStatCard: View {
    let title: String
    let value: String
    let detail: String
    let accent: ActivityCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent.tint.opacity(0.88))
                    .frame(width: 10, height: 10)
                Text(title)
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Text(value)
                .productivityFont(.metric)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .help(detail)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(ProductivityTheme.elevatedBackground.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accent.tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private extension View {
    func analyticsPanelStyle() -> some View {
        self
            .padding(16)
            .background(ProductivityTheme.elevatedBackground.opacity(0.96), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(ProductivityTheme.border.opacity(0.24), lineWidth: 1)
            )
    }
}

private extension AnalyticsHourItem {
    var hourRangeLabel: String {
        let startHour = hour == 0 ? "12am" : hour < 12 ? "\(hour)am" : hour == 12 ? "12pm" : "\(hour - 12)pm"
        let endHourValue = (hour + 1) % 24
        let endHour = endHourValue == 0 ? "12am" : endHourValue < 12 ? "\(endHourValue)am" : endHourValue == 12 ? "12pm" : "\(endHourValue - 12)pm"
        return "\(startHour) - \(endHour)"
    }

    var barColor: Color {
        if productiveRatio >= 0.65 {
            return ActivityCategory.focus.tint.opacity(0.9)
        }
        if productiveRatio <= 0.35 {
            return ActivityCategory.entertainment.tint.opacity(0.85)
        }
        return ActivityCategory.research.tint.opacity(0.85)
    }
}

private struct CategoryBreakdownItem: Identifiable {
    let label: ActivityLabel
    let duration: TimeInterval
    var id: ActivityLabel { label }
}

#if DEBUG
#Preview {
    AnalyticsView(segments: [])
        .frame(width: 1180, height: 900)
}
#endif
