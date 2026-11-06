import Observation
import SQLite3
import SwiftUI

struct EmojiCalendarView: View {
    let calendarBoardStore: CalendarBoardStore
    let onBoardChanged: () -> Void
    @Environment(\.productivityTextScale) private var textScale
    @Environment(\.productivityIsFullScreen) private var isFullScreen

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate: Date?
    @State private var isGoalFormPresented = false

    private let calendar = Calendar.current
    private let quickMarkers = CalendarMarker.quickMarkers
    private let allMarkers = CalendarMarker.allMarkers

    private var pins: [String: [String]] {
        calendarBoardStore.pins
    }

    private var goals: [CalendarActivityGoal] {
        calendarBoardStore.goals
    }

    var body: some View {
        GeometryReader { proxy in
            let boardState = makeBoardState()
            let contentWidth = ProductivityTheme.contentWidth(for: proxy.size.width, isFullScreen: isFullScreen)
            let contentPadding = ProductivityTheme.contentPadding(for: proxy.size.width, isFullScreen: isFullScreen)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    goalsPanel(state: boardState)
                    calendarPanel(state: boardState)
                }
                .frame(maxWidth: contentWidth, alignment: .leading)
                .padding(contentPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(ProductivityTheme.background)
        }
        .sheet(isPresented: $isGoalFormPresented) {
            GoalFormView(
                markers: allMarkers,
                onSave: addGoal,
                onCancel: { isGoalFormPresented = false }
            )
            .frame(width: 520)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                headerCopy
                Spacer(minLength: 16)
                headerActions
            }

            VStack(alignment: .leading, spacing: 14) {
                headerCopy
                headerActions
            }
        }
    }

    private var headerCopy: some View {
        HStack(spacing: 8) {
            Text("Consistency Board")
                .productivityFont(.hero)
                .foregroundStyle(ProductivityTheme.textPrimary)
            ProductivityInfoHint(message: "Track monthly consistency, mark completed days, and manage recurring goals.")
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Button {
                jumpToToday()
            } label: {
                Label("Today", systemImage: "scope")
            }
            .buttonStyle(.bordered)

            Button {
                isGoalFormPresented = true
            } label: {
                Label("Add Goal", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            monthStepper
        }
    }

    private var monthStepper: some View {
        HStack(spacing: 8) {
            Button {
                moveMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Previous month")

            Text(monthTitle)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(minWidth: 118, minHeight: 28)
                .padding(.horizontal, 4)

            Button {
                moveMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Next month")
        }
        .padding(6)
        .background(ProductivityTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }

    private func goalsPanel(state: CalendarBoardDerivedState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Active Goals", systemImage: "target")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)

                Spacer()

                Text(goalSummaryText(for: state.goals, progressByGoalID: state.progressByGoalID))
                    .productivityFont(.captionMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            if state.goals.isEmpty {
                EmptyGoalsView {
                    isGoalFormPresented = true
                }
            } else {
                LazyVGrid(columns: goalColumns, alignment: .leading, spacing: 12) {
                    ForEach(state.goals) { goal in
                        GoalProgressCard(
                            goal: goal,
                            marker: state.marker(for: goal.markerID),
                            symbol: state.symbol(for: goal),
                            progress: state.progressByGoalID[goal.id] ?? GoalProgress(completedCount: 0, targetCount: goal.targetCount),
                            onDelete: { deleteGoal(goal) }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
        .zIndex(1)
    }

    private func calendarPanel(state: CalendarBoardDerivedState) -> some View {
        GeometryReader { proxy in
            let columns = responsiveColumns(for: proxy.size.width)
            let pinsInDisplayedMonth = state.pinsInDisplayedMonth

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    HStack(spacing: 8) {
                        Text(monthTitle)
                            .productivityFont(.sectionTitle)
                            .foregroundStyle(ProductivityTheme.textPrimary)
                        ProductivityInfoHint(message: calendarInstructionText)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if let selectedDate {
                            Text(calendar.isDateInToday(selectedDate) ? "Marking today" : "Selected \(CalendarFormatters.day.string(from: selectedDate))")
                                .productivityFont(.captionStrong)
                                .foregroundStyle(ActivityLabel.productive.tint)
                        } else if displayedMonthIsCurrentMonth {
                            Text("Select today to mark it")
                                .productivityFont(.captionStrong)
                                .foregroundStyle(ActivityLabel.productive.tint)
                        }

                        Text("\(pinsInDisplayedMonth) marked \(pinsInDisplayedMonth == 1 ? "day" : "days")")
                            .productivityFont(.captionMedium)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                    }
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(weekdaySymbols, id: \.self) { weekday in
                        Text(weekday)
                            .productivityFont(.captionStrong)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(state.monthDays) { day in
                        CalendarDayCell(
                            day: day,
                            markers: state.markers(for: state.normalizedPinsByKey[day.key] ?? []),
                            quickMarkers: state.visibleQuickMarkers,
                            allMarkers: state.selectableMarkers,
                            goalNamesByMarkerID: state.goalNamesByMarkerID,
                            goalSymbolsByMarkerID: state.goalSymbolsByMarkerID,
                            isSelected: isSelected(day.date),
                            isToday: calendar.isDateInToday(day.date),
                            selectAction: {
                                toggleSelectedDate(day.date)
                            },
                            toggleMarkerAction: toggleMarker
                        )
                    }
                }
            }
            .padding(18)
            .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(displayedMonthIsCurrentMonth ? ActivityLabel.productive.tint.opacity(0.24) : ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
        }
        .frame(minHeight: 650)
    }

    private var goalColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 230, maximum: 360), spacing: 12, alignment: .top)]
    }

    private func makeBoardState() -> CalendarBoardDerivedState {
        CalendarBoardDerivedState(
            goals: goals,
            pins: pins,
            displayedMonth: displayedMonth,
            calendar: calendar,
            quickMarkers: quickMarkers,
            allMarkers: allMarkers
        )
    }

    private func goalSummaryText(
        for goals: [CalendarActivityGoal],
        progressByGoalID: [UUID: GoalProgress]
    ) -> String {
        let completeCount = goals.filter { progressByGoalID[$0.id]?.isComplete == true }.count
        guard !goals.isEmpty else { return "No goals yet" }
        return completeCount == 0
            ? "No goals completed yet"
            : "\(completeCount) of \(goals.count) completed so far"
    }

    private func responsiveColumns(for width: CGFloat) -> [GridItem] {
        let spacing: CGFloat = 10
        let minimumCellWidth: CGFloat = width < 700 ? 72 : 96
        let availableWidth = max(1, width - 36 - (spacing * 6))
        let cellWidth = max(minimumCellWidth, availableWidth / 7)
        return Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: 7)
    }

    private var weekdaySymbols: [String] {
        calendar.shortStandaloneWeekdaySymbols.rotatedLeft(by: calendar.firstWeekday - 1)
    }

    private var monthTitle: String {
        CalendarFormatters.month.string(from: displayedMonth)
    }

    private var displayedMonthIsCurrentMonth: Bool {
        calendar.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    private var calendarInstructionText: String {
        if let selectedDate {
            return "Select a day to mark the habits or goals you completed. \(calendar.isDateInToday(selectedDate) ? "Today is ready to log." : "This day is ready to log.")"
        }

        return "Select a day to mark the habits or goals you completed."
    }

    private var selectedDateKey: String? {
        guard let selectedDate else { return nil }
        return EmojiPinStorage.key(for: selectedDate, calendar: calendar)
    }

    private func isSelected(_ date: Date) -> Bool {
        guard let selectedDate else { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func toggleSelectedDate(_ date: Date) {
        withAnimation(.smooth(duration: 0.22)) {
            if isSelected(date) {
                selectedDate = nil
            } else {
                selectedDate = date
            }
        }
    }

    private func moveMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = calendar.startOfMonth(for: newMonth)
            selectedDate = nil
        }
    }

    private func jumpToToday() {
        let today = Date()
        withAnimation(.smooth(duration: 0.22)) {
            displayedMonth = calendar.startOfMonth(for: today)
            selectedDate = today
        }
    }

    private func toggleMarker(_ marker: CalendarMarker) {
        guard let selectedDateKey else { return }

        var updatedPins = pins
        var dayPins = normalizedPinIDs(updatedPins[selectedDateKey] ?? [])

        if dayPins.contains(marker.id) {
            dayPins.removeAll { $0 == marker.id }
        } else {
            dayPins.append(marker.id)
        }

        if dayPins.isEmpty {
            updatedPins.removeValue(forKey: selectedDateKey)
        } else {
            updatedPins[selectedDateKey] = dayPins
        }

        calendarBoardStore.replacePins(updatedPins)
        onBoardChanged()
    }

    private func normalizedPinIDs(_ ids: [String]) -> [String] {
        CalendarBoardDerivedState.normalizedPinIDs(ids)
    }

    private func addGoal(_ goal: CalendarActivityGoal) {
        var updatedGoals = goals
        updatedGoals.append(goal)
        calendarBoardStore.replaceGoals(updatedGoals)
        onBoardChanged()
        isGoalFormPresented = false
    }

    private func deleteGoal(_ goal: CalendarActivityGoal) {
        let updatedGoals = goals.filter { $0.id != goal.id }
        calendarBoardStore.replaceGoals(updatedGoals)

        if goal.isCustomMarker {
            var updatedPins = pins
            for key in updatedPins.keys {
                let filteredPins = normalizedPinIDs(updatedPins[key] ?? [])
                    .filter { $0 != goal.markerID }
                if filteredPins.isEmpty {
                    updatedPins.removeValue(forKey: key)
                } else {
                    updatedPins[key] = filteredPins
                }
            }
            calendarBoardStore.replacePins(updatedPins)
        }

        onBoardChanged()
    }

}

@MainActor
private struct CalendarBoardDerivedState {
    let goals: [CalendarActivityGoal]
    let normalizedPinsByKey: [String: [String]]
    let monthDays: [CalendarDay]
    let selectableMarkers: [CalendarMarker]
    let visibleQuickMarkers: [CalendarMarker]
    let goalNamesByMarkerID: [String: String]
    let goalSymbolsByMarkerID: [String: String]
    let progressByGoalID: [UUID: GoalProgress]
    let pinsInDisplayedMonth: Int

    private let markerByID: [String: CalendarMarker]

    init(
        goals: [CalendarActivityGoal],
        pins: [String: [String]],
        displayedMonth: Date,
        calendar: Calendar,
        quickMarkers: [CalendarMarker],
        allMarkers: [CalendarMarker]
    ) {
        self.goals = goals

        let normalizedPinsByKey = pins.mapValues(Self.normalizedPinIDs)
        let datedPins = pins.compactMap { key, ids -> DatedCalendarPins? in
            guard let date = EmojiPinStorage.date(for: key, calendar: calendar) else { return nil }
            return DatedCalendarPins(date: date, markerIDs: Set(Self.normalizedPinIDs(ids)))
        }
        let customGoalMarkers = goals.compactMap(CalendarMarker.custom)
        let selectableMarkers = Self.uniqueMarkers(customGoalMarkers + allMarkers)
        let monthDays = Self.makeMonthDays(displayedMonth: displayedMonth, calendar: calendar)

        self.normalizedPinsByKey = normalizedPinsByKey
        self.monthDays = monthDays
        self.selectableMarkers = selectableMarkers
        self.visibleQuickMarkers = Self.uniqueMarkers(customGoalMarkers + quickMarkers)
        self.markerByID = Dictionary(uniqueKeysWithValues: selectableMarkers.map { ($0.id, $0) })
        self.goalNamesByMarkerID = goals.reduce(into: [:]) { names, goal in
            names[goal.markerID] = goal.name
        }
        self.goalSymbolsByMarkerID = goals.reduce(into: [:]) { symbols, goal in
            if let symbol = Self.symbol(for: goal) {
                symbols[goal.markerID] = symbol
            }
        }
        self.progressByGoalID = goals.reduce(into: [:]) { progressByID, goal in
            progressByID[goal.id] = Self.progress(
                for: goal,
                displayedMonth: displayedMonth,
                datedPins: datedPins,
                calendar: calendar
            )
        }
        self.pinsInDisplayedMonth = monthDays.filter {
            $0.isInDisplayedMonth && !(normalizedPinsByKey[$0.key] ?? []).isEmpty
        }.count
    }

    func markers(for ids: [String]) -> [CalendarMarker] {
        ids.compactMap { markerByID[$0] }
    }

    func marker(for id: String) -> CalendarMarker {
        markerByID[id] ?? CalendarMarker.allMarkers[0]
    }

    func symbol(for goal: CalendarActivityGoal) -> String? {
        Self.symbol(for: goal)
    }

    static func normalizedPinIDs(_ ids: [String]) -> [String] {
        var seenIDs = Set<String>()
        return ids.reduce(into: []) { result, id in
            let normalizedID = CalendarMarker.normalizedID(for: id)
            if seenIDs.insert(normalizedID).inserted {
                result.append(normalizedID)
            }
        }
    }

    private static func makeMonthDays(displayedMonth: Date, calendar: Calendar) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let lastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end.addingTimeInterval(-1)) else {
            return []
        }

        var days: [CalendarDay] = []
        var date = firstWeek.start

        while date < lastWeek.end {
            days.append(CalendarDay(
                date: date,
                isInDisplayedMonth: calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                calendar: calendar
            ))

            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = nextDate
        }

        return days
    }

    private static func uniqueMarkers(_ markers: [CalendarMarker]) -> [CalendarMarker] {
        var seenIDs = Set<String>()
        return markers.reduce(into: []) { result, marker in
            if seenIDs.insert(marker.id).inserted {
                result.append(marker)
            }
        }
    }

    private static func symbol(for goal: CalendarActivityGoal) -> String? {
        guard goal.isCustomMarker else { return nil }
        return goal.symbol?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private static func progress(
        for goal: CalendarActivityGoal,
        displayedMonth: Date,
        datedPins: [DatedCalendarPins],
        calendar: Calendar
    ) -> GoalProgress {
        guard let interval = goal.period.progressInterval(displayedMonth: displayedMonth, calendar: calendar) else {
            return GoalProgress(completedCount: 0, targetCount: goal.targetCount)
        }

        let completedCount = datedPins.reduce(0) { count, datedPin in
            guard interval.contains(datedPin.date),
                  datedPin.markerIDs.contains(goal.markerID) else {
                return count
            }

            return count + 1
        }

        return GoalProgress(completedCount: completedCount, targetCount: goal.targetCount)
    }
}

private struct DatedCalendarPins {
    let date: Date
    let markerIDs: Set<String>
}

private struct EmptyGoalsView: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Create your first consistency goal")
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text("Choose an activity marker, name it, and set a weekly or monthly frequency.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProductivityTheme.subtleBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct GoalProgressCard: View {
    let goal: CalendarActivityGoal
    let marker: CalendarMarker
    let symbol: String?
    let progress: GoalProgress
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                PersonalizedMarkerGlyph(marker: marker, symbol: symbol, size: 36, iconSize: 17, isSelected: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.name)
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Text("\(goal.targetCount) \(goal.period.unitTitle)")
                        .productivityFont(.captionMedium)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Spacer(minLength: 8)

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete goal")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(progress.completedCount)")
                        .productivityFont(.metricProminent)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text("/ \(goal.targetCount)")
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textSecondary)

                    Spacer()

                    Text(progress.statusTitle)
                        .productivityFont(.captionStrong)
                        .foregroundStyle(progress.isComplete ? ActivityLabel.productive.tint : ProductivityTheme.textSecondary)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ProductivityTheme.subtleBackground)
                        Capsule()
                            .fill(marker.tint)
                            .frame(width: proxy.size.width * progress.fraction)
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(ProductivityTheme.subtleBackground.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(marker.tint.opacity(progress.isComplete ? 0.48 : 0.22), lineWidth: 1)
        )
    }
}

private struct GoalFormView: View {
    let markers: [CalendarMarker]
    let onSave: (CalendarActivityGoal) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var customSymbol = ""
    @State private var isCustomMarkerSelected = false
    @State private var selectedMarkerID = CalendarMarker.quickMarkers[0].id
    @State private var period = GoalPeriod.weekly
    @State private var targetCount = 4
    @FocusState private var isTargetFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Goal")
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            TextField("Activity name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Frequency", selection: $period) {
                ForEach(GoalPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)

            targetEditor

            VStack(alignment: .leading, spacing: 10) {
                Text("Marker")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)

                Button {
                    isCustomMarkerSelected = true
                } label: {
                    CustomMarkerChoiceTile(symbol: trimmedCustomSymbol, isSelected: isCustomMarkerSelected)
                }
                .buttonStyle(.plain)
                .help("Create a custom marker")

                LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                    ForEach(markers) { marker in
                        Button {
                            isCustomMarkerSelected = false
                            selectedMarkerID = marker.id
                        } label: {
                            MarkerGlyph(
                                marker: marker,
                                size: 34,
                                iconSize: 16,
                                isSelected: selectedMarkerID == marker.id
                            )
                        }
                        .buttonStyle(.plain)
                        .help(marker.title)
                    }
                }

                if isCustomMarkerSelected {
                    HStack(spacing: 10) {
                        TextField("Emoji", text: $customSymbol)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 86)
                            .multilineTextAlignment(.center)

                        Text("Custom marker")
                            .productivityFont(.bodyMedium)
                            .foregroundStyle(ProductivityTheme.textPrimary)

                        Spacer()
                    }
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Add") {
                    onSave(CalendarActivityGoal(
                        name: trimmedName,
                        markerID: markerIDForSave,
                        symbol: isCustomMarkerSelected ? trimmedCustomSymbol : nil,
                        targetCount: targetCount,
                        period: period
                    ))
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(18)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
        .onChange(of: period) { _, newPeriod in
            targetCount = targetCount.clamped(to: 1...newPeriod.maximumTarget)
        }
    }

    private var targetEditor: some View {
        HStack(spacing: 12) {
            Text("Target")
                .foregroundStyle(ProductivityTheme.textPrimary)

            TextField("Days", value: targetBinding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
                .multilineTextAlignment(.center)
                .focused($isTargetFieldFocused)

            Text(period.unitTitle)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textSecondary)

            Spacer()

            Stepper("", value: $targetCount, in: 1...period.maximumTarget)
                .labelsHidden()
                .frame(width: 62)
        }
    }

    private var targetBinding: Binding<Int> {
        Binding(
            get: { targetCount },
            set: { newValue in
                targetCount = newValue.clamped(to: 1...period.maximumTarget)
            }
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCustomSymbol: String? {
        customSymbol.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private var markerIDForSave: String {
        isCustomMarkerSelected ? "\(CalendarMarker.customMarkerIDPrefix)\(UUID().uuidString)" : selectedMarkerID
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (!isCustomMarkerSelected || trimmedCustomSymbol != nil)
    }
}

private struct CalendarDayCell: View {
    let day: CalendarDay
    let markers: [CalendarMarker]
    let quickMarkers: [CalendarMarker]
    let allMarkers: [CalendarMarker]
    let goalNamesByMarkerID: [String: String]
    let goalSymbolsByMarkerID: [String: String]
    let isSelected: Bool
    let isToday: Bool
    let selectAction: () -> Void
    let toggleMarkerAction: (CalendarMarker) -> Void

    @State private var isMarkerPickerPresented = false

    var body: some View {
        VStack(spacing: 8) {
            Button(action: selectAction) {
                VStack(spacing: 6) {
                    HStack {
                        dateBadge

                        Spacer(minLength: 0)
                    }

                    HStack(spacing: 4) {
                        ForEach(markers.prefix(4)) { marker in
                            PersonalizedMarkerGlyph(
                                marker: marker,
                                symbol: goalSymbolsByMarkerID[marker.id],
                                size: 18,
                                iconSize: 9,
                                isSelected: true
                            )
                                .help(goalNamesByMarkerID[marker.id] ?? marker.title)
                        }

                        if markers.count > 4 {
                            Text("+")
                                .productivityFont(.noteStrong)
                                .foregroundStyle(ProductivityTheme.textSecondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(height: 18, alignment: .leading)

                    if !markers.isEmpty {
                        Text(markersLabel)
                            .productivityFont(.noteMedium)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(9)
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
                .background(backgroundFill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: isSelected ? 1.4 : 1)
                )
            }
            .buttonStyle(.plain)

            if isSelected {
                selectedEditor
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .opacity(day.isInDisplayedMonth ? 1 : 0.55)
        .onChange(of: isSelected) { _, newValue in
            if !newValue {
                isMarkerPickerPresented = false
            }
        }
    }

    private var selectedEditor: some View {
        HStack(spacing: 5) {
            ForEach(quickMarkers) { marker in
                Button {
                    toggleMarkerAction(marker)
                } label: {
                    PersonalizedMarkerGlyph(
                        marker: marker,
                        symbol: goalSymbolsByMarkerID[marker.id],
                        size: 24,
                        iconSize: 11,
                        isSelected: markers.contains(marker)
                    )
                }
                .buttonStyle(.plain)
                .help(goalNamesByMarkerID[marker.id] ?? marker.title)
            }

            Button {
                isMarkerPickerPresented.toggle()
            } label: {
                Image(systemName: "plus")
                    .productivityFont(.noteStrong)
                    .foregroundStyle(ProductivityTheme.accent)
                    .frame(width: 24, height: 23)
                    .background(ProductivityTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(ProductivityTheme.accent.opacity(0.34), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("More markers")
            .popover(isPresented: $isMarkerPickerPresented, arrowEdge: .bottom) {
                markerPicker
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.subtleBackground.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
        )
    }

    private var markerPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Markers")
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42), spacing: 8), count: 5), spacing: 8) {
                ForEach(allMarkers) { marker in
                    Button {
                        toggleMarkerAction(marker)
                    } label: {
                        PersonalizedMarkerGlyph(
                            marker: marker,
                            symbol: goalSymbolsByMarkerID[marker.id],
                            size: 34,
                            iconSize: 16,
                            isSelected: markers.contains(marker)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(goalNamesByMarkerID[marker.id] ?? marker.title)
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.5), lineWidth: 1)
        )
    }

    private var markersLabel: String {
        markers
            .prefix(2)
            .map { goalNamesByMarkerID[$0.id] ?? $0.title }
            .joined(separator: ", ")
    }

    private var dateBadge: some View {
        HStack(spacing: 6) {
            Text("\(day.number)")
                .productivityFont(isToday || isSelected ? .captionStrong : .captionMedium)
                .foregroundStyle(dateTextColor)
                .lineLimit(1)
                .frame(width: isToday ? 24 : nil, height: isToday ? 24 : nil)
                .background {
                    if isToday {
                        Circle()
                            .fill(ProductivityTheme.accent.opacity(0.22))
                    }
                }
                .overlay {
                    if isToday {
                        Circle()
                            .stroke(ProductivityTheme.accent.opacity(0.75), lineWidth: 1)
                    }
                }

            if isToday {
                Text("Today")
                    .productivityFont(.noteStrong)
                    .foregroundStyle(ProductivityTheme.accent)
                    .lineLimit(1)
            }
        }
    }

    private var dateTextColor: Color {
        if isToday { return ProductivityTheme.accent }
        return day.isInDisplayedMonth ? ProductivityTheme.textPrimary : ProductivityTheme.textSecondary.opacity(0.45)
    }

    private var backgroundFill: Color {
        if isSelected { return ProductivityTheme.accent.opacity(0.12) }
        if isToday { return ProductivityTheme.subtleBackground.opacity(0.70) }
        if !markers.isEmpty { return ProductivityTheme.subtleBackground.opacity(0.76) }
        return ProductivityTheme.subtleBackground.opacity(0.38)
    }

    private var borderColor: Color {
        if isSelected { return ProductivityTheme.accent.opacity(0.65) }
        if isToday { return ProductivityTheme.accent.opacity(0.58) }
        if !markers.isEmpty { return ProductivityTheme.accent.opacity(0.22) }
        return ProductivityTheme.border.opacity(0.32)
    }
}

struct PersonalizedMarkerGlyph: View {
    let marker: CalendarMarker
    let symbol: String?
    let size: CGFloat
    let iconSize: CGFloat
    let isSelected: Bool

    var body: some View {
        if let symbol {
            Text(symbol)
                .font(ProductivityTypography.font(.metric, scale: max(iconSize + 3, size * 0.48) / 28, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: size, height: size)
                .background(marker.tint.opacity(isSelected ? 0.24 : 0.12), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(marker.tint.opacity(isSelected ? 0.7 : 0.3), lineWidth: 1)
                )
        } else {
            MarkerGlyph(marker: marker, size: size, iconSize: iconSize, isSelected: isSelected)
        }
    }
}

private struct CustomMarkerChoiceTile: View {
    let symbol: String?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(ProductivityTheme.accent.opacity(isSelected ? 0.28 : 0.12))
                .frame(width: 34, height: 34)
                .overlay {
                    if let symbol {
                        Text(symbol)
                            .font(ProductivityTypography.font(.sectionTitle, scale: 19 / 16, weight: .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    } else {
                        Image(systemName: "plus")
                            .productivityFont(.controlIcon)
                            .foregroundStyle(ProductivityTheme.accent)
                    }
                }

            Text(symbol == nil ? "Custom" : "Custom marker")
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(ProductivityTheme.subtleBackground.opacity(isSelected ? 0.82 : 0.46), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    ProductivityTheme.accent.opacity(isSelected ? 0.72 : 0.42),
                    style: StrokeStyle(lineWidth: 1, dash: isSelected ? [] : [4, 4])
                )
        )
    }
}

struct MarkerGlyph: View {
    let marker: CalendarMarker
    let size: CGFloat
    let iconSize: CGFloat
    let isSelected: Bool

    init(marker: CalendarMarker, size: CGFloat, iconSize: CGFloat, isSelected: Bool = false) {
        self.marker = marker
        self.size = size
        self.iconSize = iconSize
        self.isSelected = isSelected
    }

    var body: some View {
        Image(systemName: marker.systemImage)
            .font(ProductivityTypography.font(.controlIcon, scale: iconSize / 15))
            .foregroundStyle(marker.tint)
            .frame(width: size, height: size)
            .background(marker.tint.opacity(isSelected ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(marker.tint.opacity(isSelected ? 0.74 : 0.34), lineWidth: 1)
            )
    }
}

struct CalendarActivityGoal: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var markerID: String
    var symbol: String?
    var targetCount: Int
    var period: GoalPeriod

    init(id: UUID = UUID(), name: String, markerID: String, symbol: String? = nil, targetCount: Int, period: GoalPeriod) {
        self.id = id
        self.name = name
        self.markerID = markerID
        self.symbol = symbol
        self.targetCount = targetCount
        self.period = period
    }

    var isCustomMarker: Bool {
        markerID.hasPrefix(CalendarMarker.customMarkerIDPrefix)
    }
}

enum GoalPeriod: String, CaseIterable, Identifiable, Codable {
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    var unitTitle: String {
        switch self {
        case .weekly: "days per week"
        case .monthly: "days per month"
        }
    }

    var shortUnitTitle: String {
        switch self {
        case .weekly: "this week"
        case .monthly: "this month"
        }
    }

    var maximumTarget: Int {
        switch self {
        case .weekly: 7
        case .monthly: 31
        }
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .weekly:
            calendar.mondayBased.dateInterval(of: .weekOfYear, for: date)
        case .monthly:
            calendar.dateInterval(of: .month, for: date)
        }
    }

    func progressInterval(displayedMonth: Date, calendar: Calendar) -> DateInterval? {
        switch self {
        case .weekly:
            interval(containing: Date(), calendar: calendar)
        case .monthly:
            interval(containing: displayedMonth, calendar: calendar)
        }
    }
}

struct GoalProgress {
    let completedCount: Int
    let targetCount: Int

    var fraction: CGFloat {
        guard targetCount > 0 else { return 0 }
        return min(1, CGFloat(completedCount) / CGFloat(targetCount))
    }

    var isComplete: Bool {
        completedCount >= targetCount
    }

    var statusTitle: String {
        isComplete ? "Complete" : "\(max(0, targetCount - completedCount)) to go"
    }
}

@MainActor
@Observable
final class CalendarBoardStore {
    private struct Snapshot: Codable, Equatable {
        var goals: [CalendarActivityGoal]
        var pins: [String: [String]]
    }

    private enum LegacyDefaultsKey {
        static let pins = "calendar.emojiPins"
        static let goals = "calendar.activityGoals"
    }

    private let fileManager: FileManager
    @ObservationIgnored nonisolated(unsafe) private var database: OpaquePointer?

    private(set) var goals: [CalendarActivityGoal]
    private(set) var pins: [String: [String]]

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        self.fileManager = fileManager

        // Derive SQLite URL from the legacy storeURL hint (same directory, .sqlite extension)
        let dbURL = storeURL
            .map { $0.deletingPathExtension().appendingPathExtension("sqlite") }
            ?? Self.defaultDatabaseURL(fileManager: fileManager)

        self.database = Self.openDatabase(at: dbURL, fileManager: fileManager)

        var rawGoals = Self.readGoals(from: self.database)
        var rawPins = Self.readPins(from: self.database)

        // Migrate from legacy binary plist if SQLite tables are empty
        if rawGoals.isEmpty && rawPins.isEmpty {
            let plistURLs = [
                storeURL ?? Self.defaultPlistURL(fileManager: fileManager),
                Self.legacyPlistURL(fileManager: fileManager)
            ]
            let decoder = PropertyListDecoder()
            for url in plistURLs {
                if let data = try? Data(contentsOf: url),
                   let snapshot = try? decoder.decode(Snapshot.self, from: data),
                   !snapshot.goals.isEmpty || !snapshot.pins.isEmpty {
                    rawGoals = snapshot.goals
                    rawPins = snapshot.pins
                    break
                }
            }
        }

        // Migrate from legacy UserDefaults if still empty
        if rawGoals.isEmpty && rawPins.isEmpty {
            let legacyGoals = GoalStorage.decode(
                UserDefaults.standard.string(forKey: LegacyDefaultsKey.goals) ?? "[]"
            )
            let legacyPins = EmojiPinStorage.decodeDictionary(
                UserDefaults.standard.string(forKey: LegacyDefaultsKey.pins) ?? "{}"
            )
            if !legacyGoals.isEmpty || !legacyPins.isEmpty {
                rawGoals = legacyGoals
                rawPins = legacyPins
            }
        }

        self.goals = Self.normalizedGoals(rawGoals)
        self.pins = Self.normalizedPins(rawPins)

        // Persist migrated data and clean up legacy UserDefaults keys
        if !self.goals.isEmpty || !self.pins.isEmpty {
            Self.persist(goals: self.goals, pins: self.pins, to: self.database)
            UserDefaults.standard.removeObject(forKey: LegacyDefaultsKey.goals)
            UserDefaults.standard.removeObject(forKey: LegacyDefaultsKey.pins)
        }
    }

    deinit {
        sqlite3_close(database)
    }

    func replaceGoals(_ goals: [CalendarActivityGoal]) {
        self.goals = Self.normalizedGoals(goals)
        save()
    }

    func replacePins(_ pins: [String: [String]]) {
        self.pins = Self.normalizedPins(pins)
        save()
    }

    func reloadFromDisk() {
        goals = Self.normalizedGoals(Self.readGoals(from: database))
        pins = Self.normalizedPins(Self.readPins(from: database))
    }

    func clear() {
        goals = []
        pins = [:]
        save()
    }

    private func save() {
        Self.persist(goals: goals, pins: pins, to: database)
    }

    // MARK: - SQLite

    private static func openDatabase(at url: URL, fileManager: FileManager) -> OpaquePointer? {
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var db: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &db,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK else { return nil }

        sqlite3_busy_timeout(db, 250)
        sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL", nil, nil, nil)
        sqlite3_exec(db, """
            CREATE TABLE IF NOT EXISTS goals (
                id TEXT PRIMARY KEY NOT NULL,
                name TEXT NOT NULL,
                marker_id TEXT NOT NULL,
                symbol TEXT,
                target_count INTEGER NOT NULL DEFAULT 1,
                period TEXT NOT NULL DEFAULT 'weekly',
                sort_order INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS pins (
                day_key TEXT NOT NULL,
                marker_id TEXT NOT NULL,
                PRIMARY KEY (day_key, marker_id)
            );
            """, nil, nil, nil)
        return db
    }

    private static func persist(
        goals: [CalendarActivityGoal],
        pins: [String: [String]],
        to database: OpaquePointer?
    ) {
        guard let db = database else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)

        sqlite3_exec(db, "DELETE FROM goals", nil, nil, nil)
        for (index, goal) in goals.enumerated() {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db,
                "INSERT INTO goals (id, name, marker_id, symbol, target_count, period, sort_order) VALUES (?,?,?,?,?,?,?)",
                -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, goal.id.uuidString, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 2, goal.name, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 3, goal.markerID, -1, sqliteTransient)
            if let symbol = goal.symbol {
                sqlite3_bind_text(stmt, 4, symbol, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            sqlite3_bind_int(stmt, 5, Int32(goal.targetCount))
            sqlite3_bind_text(stmt, 6, goal.period.rawValue, -1, sqliteTransient)
            sqlite3_bind_int(stmt, 7, Int32(index))
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        sqlite3_exec(db, "DELETE FROM pins", nil, nil, nil)
        for (dayKey, markerIDs) in pins {
            for markerID in markerIDs {
                var stmt: OpaquePointer?
                sqlite3_prepare_v2(db,
                    "INSERT OR IGNORE INTO pins (day_key, marker_id) VALUES (?,?)",
                    -1, &stmt, nil)
                sqlite3_bind_text(stmt, 1, dayKey, -1, sqliteTransient)
                sqlite3_bind_text(stmt, 2, markerID, -1, sqliteTransient)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
        }

        sqlite3_exec(db, "COMMIT", nil, nil, nil)
    }

    private static func readGoals(from database: OpaquePointer?) -> [CalendarActivityGoal] {
        guard let db = database else { return [] }
        var goals: [CalendarActivityGoal] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT id, name, marker_id, symbol, target_count, period FROM goals ORDER BY sort_order",
            -1, &stmt, nil
        ) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idText = sqlite3_column_text(stmt, 0),
                  let nameText = sqlite3_column_text(stmt, 1),
                  let markerText = sqlite3_column_text(stmt, 2),
                  let periodText = sqlite3_column_text(stmt, 5) else { continue }
            let symbol = sqlite3_column_type(stmt, 3) != SQLITE_NULL
                ? sqlite3_column_text(stmt, 3).map { String(cString: $0) }
                : nil
            goals.append(CalendarActivityGoal(
                id: UUID(uuidString: String(cString: idText)) ?? UUID(),
                name: String(cString: nameText),
                markerID: String(cString: markerText),
                symbol: symbol,
                targetCount: Int(sqlite3_column_int(stmt, 4)),
                period: GoalPeriod(rawValue: String(cString: periodText)) ?? .weekly
            ))
        }
        return goals
    }

    private static func readPins(from database: OpaquePointer?) -> [String: [String]] {
        guard let db = database else { return [:] }
        var pins: [String: [String]] = [:]
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "SELECT day_key, marker_id FROM pins ORDER BY day_key, rowid",
            -1, &stmt, nil
        ) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let dayKeyText = sqlite3_column_text(stmt, 0),
                  let markerText = sqlite3_column_text(stmt, 1) else { continue }
            let dayKey = String(cString: dayKeyText)
            let markerID = String(cString: markerText)
            pins[dayKey, default: []].append(markerID)
        }
        return pins
    }

    // MARK: - URLs

    private static func defaultDatabaseURL(fileManager: FileManager) -> URL {
        let base = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ProductivityWidgetSnapshot.appGroupIdentifier
        ) ?? legacyBaseDirectory(fileManager: fileManager)
        return base
            .appendingPathComponent("CalendarBoard", isDirectory: true)
            .appendingPathComponent("board.sqlite")
    }

    private static func defaultPlistURL(fileManager: FileManager) -> URL {
        let base = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ProductivityWidgetSnapshot.appGroupIdentifier
        ) ?? legacyBaseDirectory(fileManager: fileManager)
        return base
            .appendingPathComponent("CalendarBoard", isDirectory: true)
            .appendingPathComponent("board.calendarboard")
    }

    private static func legacyPlistURL(fileManager: FileManager) -> URL {
        legacyBaseDirectory(fileManager: fileManager)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("CalendarBoard", isDirectory: true)
            .appendingPathComponent("board.calendarboard")
    }

    private static func legacyBaseDirectory(fileManager: FileManager) -> URL {
        (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
    }

    // MARK: - Normalization

    private static func normalizedGoals(_ goals: [CalendarActivityGoal]) -> [CalendarActivityGoal] {
        goals.map { goal in
            var normalizedGoal = goal
            normalizedGoal.markerID = CalendarMarker.normalizedID(for: goal.markerID)
            normalizedGoal.targetCount = goal.targetCount.clamped(to: 1...goal.period.maximumTarget)
            return normalizedGoal
        }
    }

    private static func normalizedPins(_ pins: [String: [String]]) -> [String: [String]] {
        pins.reduce(into: [:]) { result, entry in
            let ids = entry.value.reduce(into: [String]()) { normalizedIDs, id in
                let normalizedID = CalendarMarker.normalizedID(for: id)
                if !normalizedIDs.contains(normalizedID) {
                    normalizedIDs.append(normalizedID)
                }
            }
            if !ids.isEmpty {
                result[entry.key] = ids
            }
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct CalendarMarker: Identifiable, Hashable {
    static let customMarkerIDPrefix = "custom."

    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let legacyIDs: [String]

    init(id: String, title: String, systemImage: String, tint: Color, legacyIDs: [String] = []) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.legacyIDs = legacyIDs
    }

    static let quickMarkers: [CalendarMarker] = [
        CalendarMarker(id: "star", title: "Highlight", systemImage: "star.fill", tint: Color(red: 0.70, green: 0.46, blue: 1.00), legacyIDs: ["★", "⭐"]),
        CalendarMarker(id: "workout", title: "Workout", systemImage: "figure.run", tint: Color(red: 0.24, green: 0.68, blue: 1.00), legacyIDs: ["◉", "🏃"]),
        CalendarMarker(id: "study", title: "Study", systemImage: "book.closed.fill", tint: Color(red: 0.20, green: 0.76, blue: 0.62), legacyIDs: ["✦", "📚"]),
        CalendarMarker(id: "food", title: "Food", systemImage: "fork.knife", tint: Color(red: 1.00, green: 0.58, blue: 0.24), legacyIDs: ["◌", "🍽️"]),
        CalendarMarker(id: "mindful", title: "Mindful", systemImage: "circle.hexagongrid.fill", tint: Color(red: 0.58, green: 0.50, blue: 1.00), legacyIDs: ["✓", "🧘"])
    ]

    static let allMarkers: [CalendarMarker] = quickMarkers + [
        CalendarMarker(id: "focus", title: "Deep Focus", systemImage: "scope", tint: Color(red: 0.20, green: 0.76, blue: 0.62)),
        CalendarMarker(id: "writing", title: "Writing", systemImage: "pencil.line", tint: Color(red: 0.42, green: 0.58, blue: 1.00)),
        CalendarMarker(id: "coding", title: "Coding", systemImage: "chevron.left.forwardslash.chevron.right", tint: Color(red: 0.16, green: 0.78, blue: 0.66)),
        CalendarMarker(id: "meeting", title: "Meeting", systemImage: "bubble.left.and.bubble.right.fill", tint: Color(red: 0.66, green: 0.52, blue: 1.00)),
        CalendarMarker(id: "music", title: "Music", systemImage: "music.note", tint: Color(red: 0.38, green: 0.66, blue: 1.00)),
        CalendarMarker(id: "water", title: "Hydration", systemImage: "drop.fill", tint: Color(red: 0.22, green: 0.68, blue: 1.00)),
        CalendarMarker(id: "rest", title: "Rest", systemImage: "moon.fill", tint: Color(red: 0.64, green: 0.58, blue: 0.92)),
        CalendarMarker(id: "goal", title: "Goal", systemImage: "flag.fill", tint: Color(red: 0.70, green: 0.46, blue: 1.00))
    ]

    static func legacy(_ value: String) -> CalendarMarker? {
        allMarkers.first { marker in
            marker.legacyIDs.contains(value)
        }
    }

    static func normalizedID(for value: String) -> String {
        legacy(value)?.id ?? value
    }

    static func custom(for goal: CalendarActivityGoal) -> CalendarMarker? {
        guard goal.isCustomMarker else { return nil }
        return CalendarMarker(
            id: goal.markerID,
            title: goal.name,
            systemImage: "face.smiling",
            tint: Color(red: 0.70, green: 0.46, blue: 1.00)
        )
    }
}

private struct CalendarDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let key: String
    let number: Int

    var id: String { key }

    init(date: Date, isInDisplayedMonth: Bool, calendar: Calendar) {
        self.date = calendar.startOfDay(for: date)
        self.isInDisplayedMonth = isInDisplayedMonth
        key = EmojiPinStorage.key(for: date, calendar: calendar)
        number = calendar.component(.day, from: date)
    }
}

enum GoalStorage {
    static func decode(_ value: String) -> [CalendarActivityGoal] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([CalendarActivityGoal].self, from: data) else {
            return []
        }

        return decoded
    }

    static func encode(_ value: [CalendarActivityGoal]) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encodedValue = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return encodedValue
    }
}

enum EmojiPinStorage {
    static func key(for date: Date, calendar: Calendar) -> String {
        CalendarFormatters.key.string(from: calendar.startOfDay(for: date))
    }

    static func date(for key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }

        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        ))
    }

    static func decodeDictionary(_ value: String) -> [String: [String]] {
        guard let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) else {
            return [:]
        }

        return decoded
    }

    static func encode<T: Encodable>(_ value: T) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encodedValue = String(data: data, encoding: .utf8) else {
            return ""
        }

        return encodedValue
    }
}

private enum CalendarFormatters {
    static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    static let key: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        dateInterval(of: .month, for: date)?.start ?? startOfDay(for: date)
    }
}

private extension Array {
    func rotatedLeft(by distance: Int) -> [Element] {
        guard !isEmpty else { return [] }
        let offset = ((distance % count) + count) % count
        return Array(self[offset...]) + Array(self[..<offset])
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

#if DEBUG
#Preview {
    EmojiCalendarView(calendarBoardStore: CalendarBoardStore(), onBoardChanged: {})
        .frame(width: 1120, height: 760)
        .preferredColorScheme(.dark)
}
#endif
