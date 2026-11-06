import SwiftUI

/// An interactive pull-cord component that allows users to drag down to set a timer duration.
struct PullTimerInteractiveCordView: View {
    let viewModel: PomodoroViewModel
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false

    private var calculatedMinutes: Int {
        PullTimerDurationCalculator.calculateDuration(dragDistanceY: dragOffset)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Pull to Set Timer", systemImage: "arrow.down.circle.dotted")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                Spacer()
                if isDragging && calculatedMinutes > 0 {
                    Text(PullTimerDurationCalculator.shortFormattedDuration(minutes: calculatedMinutes))
                        .productivityFont(.captionStrong)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(ProductivityTheme.accent.opacity(0.18))
                        .foregroundStyle(ProductivityTheme.accent)
                        .clipShape(Capsule())
                }
            }

            ZStack(alignment: .top) {
                // Cord path
                Canvas { context, size in
                    guard isDragging && dragOffset > 4 else { return }
                    let start = CGPoint(x: size.width / 2, y: 0)
                    let end = CGPoint(x: size.width / 2, y: dragOffset)

                    var path = Path()
                    path.move(to: start)
                    let midX = size.width / 2
                    let midY = dragOffset / 2
                    path.addQuadCurve(to: end, control: CGPoint(x: midX, y: midY))

                    context.stroke(
                        path,
                        with: .color(ProductivityTheme.accent.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                }
                .frame(height: max(40, dragOffset + 36))

                // Anchor Pin
                Circle()
                    .fill(ProductivityTheme.accent)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
                    )

                // Drag Handle Pill
                HStack(spacing: 6) {
                    Image(systemName: isDragging ? "timer" : "hand.draw")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isDragging ? PullTimerDurationCalculator.formattedDuration(minutes: calculatedMinutes) : "Pull down to set timer")
                        .productivityFont(.caption)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDragging ? ProductivityTheme.accent.opacity(0.24) : ProductivityTheme.subtleBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isDragging ? ProductivityTheme.accent : Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .offset(y: dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            isDragging = true
                            dragOffset = max(0, min(value.translation.height, 260))
                        }
                        .onEnded { _ in
                            let minutes = calculatedMinutes
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                dragOffset = 0
                                isDragging = false
                            }
                            if minutes >= 1 {
                                viewModel.setFocusDuration(minutes, resetTimer: true, startImmediately: true)
                            }
                        }
                )
            }
            .frame(height: isDragging ? max(50, dragOffset + 44) : 46)
            .animation(.interactiveSpring(), value: dragOffset)

            if isDragging && calculatedMinutes > 0 {
                Text(PullTimerDurationCalculator.targetTimeString(minutes: calculatedMinutes))
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .transition(.opacity)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ProductivityTheme.subtleBackground.opacity(0.4))
        )
    }
}
