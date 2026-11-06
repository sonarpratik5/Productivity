import AppKit
import Observation
import SwiftUI

/// State rendered by the pull-to-set overlay. Points are in the overlay view's
/// top-left–origin coordinate space.
@MainActor
@Observable
final class PullTimerOverlayModel {
    enum Stage: Equatable {
        case hidden
        case pulling
        case cancelling
        case snappingBack
    }

    var anchor: CGPoint = .zero
    var handle: CGPoint = .zero
    var canvasSize: CGSize = .zero
    var minutes = 0
    var isFineMode = false
    var stage: Stage = .hidden
}

/// Rubber band stretched from the menu bar icon to the pulled handle.
/// Only the free end animates, so the snap-back spring drags the band with it.
private struct ElasticCordShape: Shape {
    let anchor: CGPoint
    var end: CGPoint

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(end.x, end.y) }
        set { end = CGPoint(x: newValue.first, y: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: anchor)

        let dx = end.x - anchor.x
        let dy = end.y - anchor.y
        let length = hypot(dx, dy)
        // A slack band sags a little when pulled sideways; as it stretches it pulls taut.
        let sag = min(18, abs(dx) * 0.12) * max(0.2, 1 - length / 600)
        let control = CGPoint(x: anchor.x + dx / 2, y: anchor.y + dy / 2 + sag)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

private struct PullTimerOverlayView: View {
    let model: PullTimerOverlayModel

    private static let knobDiameter: CGFloat = 12
    private static let pillGap: CGFloat = 10

    private var isCancelling: Bool { model.stage == .cancelling }
    private var isSnappingBack: Bool { model.stage == .snappingBack }

    private var tint: Color {
        isCancelling ? Color.secondary : ProductivityTheme.accent
    }

    private var cordLength: CGFloat {
        hypot(model.handle.x - model.anchor.x, model.handle.y - model.anchor.y)
    }

    /// Flip the pill to the knob's left when it would run off the screen edge.
    private var placesPillOnLeft: Bool {
        model.handle.x > model.canvasSize.width - 170
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            cord
            knob
                .position(model.handle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Cord

    /// Hairline band from the icon's center to the knob. It fades in from the icon
    /// and thins slightly as it stretches, like real elastic.
    private var cord: some View {
        let shape = ElasticCordShape(anchor: model.anchor, end: model.handle)
        let gradient = LinearGradient(
            colors: [tint.opacity(0.25), tint],
            startPoint: UnitPoint(
                x: model.anchor.x / max(model.canvasSize.width, 1),
                y: model.anchor.y / max(model.canvasSize.height, 1)
            ),
            endPoint: UnitPoint(
                x: model.handle.x / max(model.canvasSize.width, 1),
                y: model.handle.y / max(model.canvasSize.height, 1)
            )
        )
        return ZStack {
            // Soft halo keeps the hairline legible over busy wallpapers.
            shape.stroke(Color.black.opacity(0.12), style: StrokeStyle(lineWidth: cordWidth + 1.5, lineCap: .round))
            shape.stroke(gradient, style: StrokeStyle(lineWidth: cordWidth, lineCap: .round))
        }
        .opacity(isSnappingBack ? 0.6 : 1)
    }

    private var cordWidth: CGFloat {
        max(1, 1.6 - cordLength / 500)
    }

    // MARK: Knob + pill

    private var knob: some View {
        Circle()
            .fill(tint)
            .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
            .frame(width: Self.knobDiameter, height: Self.knobDiameter)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .overlay(alignment: placesPillOnLeft ? .trailing : .leading) {
                pill
                    .fixedSize()
                    .offset(x: (Self.knobDiameter + Self.pillGap) * (placesPillOnLeft ? -1 : 1))
                    .opacity(isSnappingBack ? 0 : 1)
                    .scaleEffect(isSnappingBack ? 0.9 : 1, anchor: placesPillOnLeft ? .trailing : .leading)
            }
            // Retract into the menu bar icon while springing back.
            .scaleEffect(isSnappingBack ? 0.3 : 1)
            .opacity(isSnappingBack ? 0 : 1)
    }

    private var pill: some View {
        HStack(spacing: 6) {
            if isCancelling {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Text(durationText)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(model.minutes)))
                .foregroundStyle(isCancelling ? .secondary : .primary)

            if let endTimeText {
                Circle()
                    .fill(.tertiary)
                    .frame(width: 2.5, height: 2.5)
                Text(endTimeText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if model.isFineMode && !isCancelling {
                Image(systemName: "scope")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ProductivityTheme.accent)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .animation(.snappy(duration: 0.18), value: model.minutes)
        .animation(.snappy(duration: 0.18), value: model.isFineMode)
        .animation(.snappy(duration: 0.18), value: isCancelling)
    }

    /// "25 min", "1h 30m", or "Cancel".
    private var durationText: String {
        guard !isCancelling, model.minutes > 0 else { return "Cancel" }
        return model.minutes < 60
            ? "\(model.minutes) min"
            : PullTimerDurationCalculator.shortFormattedDuration(minutes: model.minutes)
    }

    private var endTimeText: String? {
        guard !isCancelling, model.minutes > 0 else { return nil }
        let end = Date.now.addingTimeInterval(TimeInterval(model.minutes * 60))
        return end.formatted(date: .omitted, time: .shortened)
    }
}

/// Transparent, click-through window that hosts the pull overlay on the icon's screen.
private final class PullTimerOverlayWindow: NSPanel {
    init(rootView: some View) {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        let hostingView = NSHostingView(rootView: rootView)
        // The window is sized explicitly to the screen; never let SwiftUI resize it.
        hostingView.sizingOptions = []
        contentView = hostingView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // Sit just above the menu bar so the handle can overlap it during snap-back.
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Drives the overlay shown while the menu bar icon is being pulled.
@MainActor
final class PullTimerOverlayController {
    private let model = PullTimerOverlayModel()
    private lazy var window = PullTimerOverlayWindow(rootView: PullTimerOverlayView(model: model))
    /// Incremented per gesture so a stale snap-back completion never hides a newer pull.
    private var generation = 0

    /// Shows the detached handle. `anchor` and `handle` are screen coordinates.
    func begin(anchor: CGPoint, handle: CGPoint) {
        generation += 1
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let screen else { return }

        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: false)
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.canvasSize = screen.frame.size
            model.anchor = localPoint(anchor)
            model.handle = localPoint(anchor)
            model.minutes = 0
            model.isFineMode = false
            model.stage = .pulling
        }
        window.orderFrontRegardless()

        // Pop the handle out of the icon to the pointer with a quick spring.
        withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) {
            model.handle = localPoint(handle)
        }
    }

    func update(handle: CGPoint, minutes: Int, isFineMode: Bool, isCancelling: Bool) {
        guard model.stage == .pulling || model.stage == .cancelling else { return }
        model.handle = clampedLocalPoint(handle)
        model.minutes = minutes
        model.isFineMode = isFineMode
        model.stage = isCancelling ? .cancelling : .pulling
    }

    /// Springs the handle back into the menu bar with a rubber-band overshoot, then hides.
    func snapBack() {
        guard model.stage != .hidden else { return }
        let token = generation
        withAnimation(.spring(response: 0.38, dampingFraction: 0.52)) {
            model.stage = .snappingBack
            model.handle = model.anchor
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.hide()
        }
    }

    func hide() {
        model.stage = .hidden
        window.orderOut(nil)
    }

    private func localPoint(_ screenPoint: CGPoint) -> CGPoint {
        let frame = window.frame
        return CGPoint(x: screenPoint.x - frame.minX, y: frame.maxY - screenPoint.y)
    }

    private func clampedLocalPoint(_ screenPoint: CGPoint) -> CGPoint {
        let point = localPoint(screenPoint)
        let size = model.canvasSize
        return CGPoint(x: min(max(point.x, 0), size.width), y: min(max(point.y, 0), size.height))
    }
}
