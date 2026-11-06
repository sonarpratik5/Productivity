import AppKit
import SwiftUI

struct PomodoroMenuBarView: View {
    let viewModel: PomodoroViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressBar
            controls

            Divider()

            Button {
                openWindow(id: "main")
                NSApplication.shared.activate(ignoringOtherApps: true)
            } label: {
                Label("Open App", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit FocusGrove", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
        .padding(16)
        .frame(width: 320)
        .background(Color.clear)
        .containerBackground(
            ProductivityTheme.background.opacity(0.82),
            for: .window
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(ProductivityTheme.accent.opacity(0.16))
                Image(systemName: viewModel.phase.systemImage)
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.phase.title)
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text(viewModel.isRunning ? "Running" : "Ready")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Spacer()

            Text(viewModel.formattedRemainingTime)
                .font(ProductivityTypography.font(.metricMonospaced))
                .foregroundStyle(ProductivityTheme.textPrimary)
                .contentTransition(.numericText())
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ProductivityTheme.subtleBackground)
                RoundedRectangle(cornerRadius: 4)
                    .fill(ProductivityTheme.accent.gradient)
                    .frame(width: proxy.size.width * viewModel.progress)
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.smooth(duration: 0.28), value: viewModel.progress)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleRunning()
            } label: {
                Label(viewModel.isRunning ? "Pause" : "Start", systemImage: viewModel.isRunning ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 30)
            }
            .help("Reset")

            Button {
                viewModel.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 30)
            }
            .help("Skip")
        }
        .controlSize(.large)
    }

    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Presets")
                .productivityFont(.captionMedium)
                .foregroundStyle(ProductivityTheme.textSecondary)

            HStack(spacing: 6) {
                ForEach(PomodoroViewModel.presetFocusDurations, id: \.self) { minutes in
                    Button {
                        viewModel.setFocusDuration(minutes)
                    } label: {
                        Text("\(minutes)m")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(
                        viewModel.configuration.focusMinutes == minutes && viewModel.phase == .focus
                            ? ProductivityTheme.accent.opacity(0.25)
                            : ProductivityTheme.elevatedBackground,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                viewModel.configuration.focusMinutes == minutes && viewModel.phase == .focus
                                    ? ProductivityTheme.accent
                                    : ProductivityTheme.border.opacity(0.35),
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(
                        viewModel.configuration.focusMinutes == minutes && viewModel.phase == .focus
                            ? ProductivityTheme.accent
                            : ProductivityTheme.textPrimary
                    )
                }
            }
        }
    }

    private var phaseSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Phase", selection: Binding(
                get: { viewModel.phase },
                set: { viewModel.selectPhase($0) }
            )) {
                ForEach(PomodoroPhase.allCases) { phase in
                    Text(phase.title).tag(phase)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 8) {
                menuStepper(
                    title: "Focus",
                    value: Binding(
                        get: { viewModel.configuration.focusMinutes },
                        set: { viewModel.setFocusDuration($0) }
                    ),
                    range: PomodoroConfiguration.focusMinutesRange,
                    suffix: "min"
                )

                menuStepper(
                    title: "Short Break",
                    value: Binding(
                        get: { viewModel.configuration.shortBreakMinutes },
                        set: { viewModel.setShortBreakDuration($0) }
                    ),
                    range: PomodoroConfiguration.shortBreakMinutesRange,
                    suffix: "min"
                )

                menuStepper(
                    title: "Long Break",
                    value: Binding(
                        get: { viewModel.configuration.longBreakMinutes },
                        set: { viewModel.setLongBreakDuration($0) }
                    ),
                    range: PomodoroConfiguration.longBreakMinutesRange,
                    suffix: "min"
                )

                menuStepper(
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
    }

    private func menuStepper(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        suffix: String
    ) -> some View {
        HStack {
            Text(title)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)

            Spacer()

            Text("\(value.wrappedValue) \(suffix)")
                .font(ProductivityTypography.font(.noteMonospaced, weight: .semibold))
                .foregroundStyle(ProductivityTheme.textPrimary)

            Stepper("", value: value, in: range)
                .labelsHidden()
                .controlSize(.mini)
        }
    }
}
