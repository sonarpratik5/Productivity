import SwiftUI

struct PomodoroView: View {
    let viewModel: PomodoroViewModel
    @Environment(\.productivityTextScale) private var textScale
    @Environment(\.productivityIsFullScreen) private var isFullScreen

    init(viewModel: PomodoroViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = ProductivityTheme.contentWidth(for: proxy.size.width, isFullScreen: isFullScreen)
            let contentPadding = ProductivityTheme.contentPadding(for: proxy.size.width, isFullScreen: isFullScreen)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    timerPanel
                    secondaryPanels
                }
                .padding(contentPadding)
                .frame(maxWidth: contentWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollContentBackground(.hidden)
            .background(ProductivityTheme.background)
        }
        .animation(.smooth(duration: 0.24), value: viewModel.phase)
        .animation(.smooth(duration: 0.2), value: viewModel.isRunning)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Pomodoro")
                .productivityFont(.hero)
                .foregroundStyle(ProductivityTheme.textPrimary)
            ProductivityInfoHint(message: "Focus timer for work and breaks.")
        }
    }

    private var timerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Primary Timer", systemImage: "scope")
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ProductivityTheme.accent.opacity(0.12), in: Capsule())

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 28) {
                    PomodoroClockView(viewModel: viewModel)
                        .frame(width: 280, height: 280)

                    timerControls(alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .timerPanelStyle(padding: 24)

                VStack(spacing: 22) {
                    PomodoroClockView(viewModel: viewModel)
                        .frame(width: 240, height: 240)

                    timerControls(alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .timerPanelStyle(padding: 18)
            }
        }
    }

    private func timerControls(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 18) {
            phasePicker
                .frame(maxWidth: 420, alignment: alignment == .center ? .center : .leading)
            controls
            sessionStatus(alignment: alignment)
        }
    }

    private var phasePicker: some View {
        Picker("Phase", selection: Binding(
            get: { viewModel.phase },
            set: { viewModel.selectPhase($0) }
        )) {
            ForEach(PomodoroPhase.allCases) { phase in
                Text(phase.title)
                    .tag(phase)
            }
        }
        .pickerStyle(.segmented)
        .animation(.smooth(duration: 0.22), value: viewModel.phase)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                controlButtons
            }

            VStack(spacing: 10) {
                controlButtons
            }
        }
    }

    @ViewBuilder
    private var controlButtons: some View {
        Button {
            viewModel.toggleRunning()
        } label: {
            Label(viewModel.isRunning ? "Pause" : "Start", systemImage: viewModel.isRunning ? "pause.fill" : "play.fill")
                .frame(minWidth: 116)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .contentTransition(.opacity)

        Button {
            viewModel.reset()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .frame(minWidth: 104)
        }
        .controlSize(.large)

        Button {
            viewModel.skip()
        } label: {
            Label("Skip", systemImage: "forward.end.fill")
                .frame(minWidth: 96)
        }
        .controlSize(.large)
    }

    private func sessionStatus(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(viewModel.phase.title)
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .contentTransition(.opacity)
            Text("Completed focus sessions today: \(viewModel.completedFocusSessions)")
                .productivityFont(.bodyMonospaced)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .contentTransition(.numericText())
            Text("\(viewModel.totalFocusMinutesToday) focus minutes logged today")
                .productivityFont(.captionMonospaced)
                .foregroundStyle(ProductivityTheme.textSecondary.opacity(0.86))
                .contentTransition(.numericText())
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }

    private var secondaryPanels: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    PomodoroConfigurationView(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    PomodoroHistorySection(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                VStack(alignment: .leading, spacing: 16) {
                    PomodoroConfigurationView(viewModel: viewModel)
                    PomodoroHistorySection(viewModel: viewModel)
                }
            }
        }
    }
}

private extension View {
    func timerPanelStyle(padding: CGFloat) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(
                ProductivityTheme.elevatedBackground,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [
                                ProductivityTheme.accent.opacity(0.32),
                                ProductivityTheme.accentSecondary.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: ProductivityTheme.accent.opacity(0.14), radius: 20, y: 10)
            .shadow(color: ProductivityTheme.accentSecondary.opacity(0.08), radius: 28, y: 16)
    }

    func supportingPomodoroPanelStyle() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ProductivityTheme.elevatedBackground.opacity(0.98), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct PomodoroClockView: View {
    let viewModel: PomodoroViewModel

    var body: some View {
        ZStack {
            Circle()
                .fill(ProductivityTheme.subtleBackground.opacity(0.7))

            Circle()
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 18)
                .padding(20)

            Circle()
                .trim(from: 0, to: viewModel.progress)
                .stroke(
                    ProductivityTheme.accent.gradient,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(20)
                .animation(.smooth(duration: 0.35), value: viewModel.progress)

            VStack(spacing: 10) {
                Image(systemName: viewModel.phase.systemImage)
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.accent)

                Text(viewModel.formattedRemainingTime)
                    .font(ProductivityTypography.font(.metricHeroMonospaced))
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .minimumScaleFactor(0.72)
                    .contentTransition(.numericText())

                Text(viewModel.isRunning ? "Running" : "Ready")
                    .productivityFont(.captionMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .contentTransition(.opacity)
            }
            .padding(24)
        }
    }
}

private struct PomodoroConfigurationView: View {
    let viewModel: PomodoroViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Text("Timer Setup")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                ProductivityInfoHint(message: "Adjust durations when you want to tune the ritual, not while you are trying to focus.")
            }

            LazyVGrid(columns: columns, spacing: 12) {
                PomodoroStepperCard(
                    title: "Focus",
                    value: Binding(
                        get: { viewModel.configuration.focusMinutes },
                        set: { viewModel.configuration.focusMinutes = $0 }
                    ),
                    range: PomodoroConfiguration.focusMinutesRange,
                    suffix: "min"
                )

                PomodoroStepperCard(
                    title: "Short Break",
                    value: Binding(
                        get: { viewModel.configuration.shortBreakMinutes },
                        set: { viewModel.configuration.shortBreakMinutes = $0 }
                    ),
                    range: PomodoroConfiguration.shortBreakMinutesRange,
                    suffix: "min"
                )

                PomodoroStepperCard(
                    title: "Long Break",
                    value: Binding(
                        get: { viewModel.configuration.longBreakMinutes },
                        set: { viewModel.configuration.longBreakMinutes = $0 }
                    ),
                    range: PomodoroConfiguration.longBreakMinutesRange,
                    suffix: "min"
                )

                PomodoroStepperCard(
                    title: "Long Break Every",
                    value: Binding(
                        get: { viewModel.configuration.sessionsBeforeLongBreak },
                        set: { viewModel.configuration.sessionsBeforeLongBreak = $0 }
                    ),
                    range: PomodoroConfiguration.sessionsBeforeLongBreakRange,
                    suffix: "sessions"
                )
            }
        }
        .supportingPomodoroPanelStyle()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 12)]
    }
}

private struct PomodoroHistorySection: View {
    let viewModel: PomodoroViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Text("Recent Focus History")
                        .productivityFont(.sectionTitle)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    ProductivityInfoHint(message: "A quiet record of completed focus blocks for reflection.")
                }

                Spacer()

                Text("\(viewModel.completedFocusSessions) today")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            if viewModel.recentSessionHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No completed sessions yet")
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text("Complete one session to populate this list.")
                        .productivitySupportingNoteStyle()
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ProductivityTheme.subtleBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.recentSessionHistory) { session in
                        PomodoroHistoryRow(session: session)
                    }
                }
            }
        }
        .supportingPomodoroPanelStyle()
    }
}

private struct PomodoroHistoryRow: View {
    let session: PomodoroSessionRecord

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(ProductivityTheme.subtleBackground.opacity(0.72))
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ActivityLabel.productive.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(timeText)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text(dateText)
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Spacer()

            Text("\(session.focusMinutes) min")
                .font(ProductivityTypography.font(.bodyMonospaced, weight: .semibold))
                .foregroundStyle(ProductivityTheme.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(ActivityLabel.productive.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
    }

    private var timeText: String {
        PomodoroHistoryFormatters.time.string(from: session.completedAt)
    }

    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(session.completedAt) {
            return "Today"
        }
        if calendar.isDateInYesterday(session.completedAt) {
            return "Yesterday"
        }
        return PomodoroHistoryFormatters.day.string(from: session.completedAt)
    }
}

private enum PomodoroHistoryFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter
    }()
}

private struct PomodoroStepperCard: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .productivityFont(.captionMedium)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(value)")
                    .font(ProductivityTypography.font(.metricMonospaced))
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .contentTransition(.numericText())
                Text(suffix)
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Stepper(title, value: $value, in: range)
                .labelsHidden()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.subtleBackground.opacity(0.76), in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview {
    PomodoroView(viewModel: PomodoroViewModel())
        .frame(width: 640, height: 760)
        .preferredColorScheme(.dark)
}
#endif
