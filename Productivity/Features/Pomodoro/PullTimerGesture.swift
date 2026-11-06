import CoreGraphics
import Foundation

/// Pure state machine behind "pull the menu bar icon down to set a timer".
///
/// Points are in AppKit screen coordinates (y grows upward), so pulling *down*
/// away from the menu bar means `current.y` decreases relative to `origin.y`.
/// Keeping this free of AppKit lets the gesture rules be unit tested directly.
struct PullTimerGesture: Equatable {
    enum Phase: Equatable {
        /// Mouse is down on the icon but has not been pulled past the threshold yet.
        case pressed
        /// Handle is detached from the menu bar and a duration is selected.
        case pulling
        /// Handle was pulled out, then dragged back into the menu bar: releasing cancels.
        case cancelling
    }

    enum Outcome: Equatable {
        /// Treated as a plain click on the status item.
        case click
        /// Release while pulling: start a focus timer of this many minutes.
        case start(minutes: Int)
        /// Release after the gesture was abandoned (dragged back or sideways).
        case cancel
    }

    /// Movement (in points) tolerated before a press stops counting as a click.
    static let clickSlop: CGFloat = 4
    /// Points of extra pull per minute while Shift precision mode is held.
    static let fineModePointsPerMinute: CGFloat = 6

    let origin: CGPoint
    private(set) var current: CGPoint
    private(set) var phase: Phase = .pressed
    private(set) var minutes = 0
    private(set) var isFineMode = false
    private var hasMovedBeyondClickSlop = false
    private var fineModeAnchor: FineModeAnchor?

    private struct FineModeAnchor: Equatable {
        let distance: CGFloat
        let minutes: Int
    }

    init(origin: CGPoint) {
        self.origin = origin
        self.current = origin
    }

    /// Vertical distance pulled below the press location (never negative).
    var pullDistance: CGFloat {
        max(0, origin.y - current.y)
    }

    /// Whether the handle is currently detached and should be drawn.
    var isHandleDetached: Bool {
        phase != .pressed
    }

    /// Advances the gesture to a new pointer location.
    /// - Returns: `true` when the selected minute value changed.
    @discardableResult
    mutating func update(to point: CGPoint, fineMode: Bool) -> Bool {
        let previousMinutes = minutes
        current = point

        if hypot(point.x - origin.x, point.y - origin.y) > Self.clickSlop {
            hasMovedBeyondClickSlop = true
        }

        let isBeyondThreshold = pullDistance >= PullTimerDurationCalculator.minimumDragThreshold

        switch phase {
        case .pressed:
            guard isBeyondThreshold else { return false }
            phase = .pulling
        case .pulling, .cancelling:
            phase = isBeyondThreshold ? .pulling : .cancelling
        }

        guard phase == .pulling else {
            minutes = 0
            isFineMode = false
            fineModeAnchor = nil
            return minutes != previousMinutes
        }

        if fineMode {
            // Anchor precision mode at the value shown when Shift went down so the
            // readout never jumps; from there every few points is exactly one minute.
            let anchor = fineModeAnchor ?? FineModeAnchor(
                distance: pullDistance,
                minutes: minutes > 0 ? minutes : PullTimerDurationCalculator.calculateDuration(dragDistanceY: pullDistance)
            )
            fineModeAnchor = anchor
            let delta = Int(((pullDistance - anchor.distance) / Self.fineModePointsPerMinute).rounded(.towardZero))
            minutes = Self.clampedMinutes(anchor.minutes + delta)
        } else {
            fineModeAnchor = nil
            minutes = PullTimerDurationCalculator.calculateDuration(dragDistanceY: pullDistance)
        }

        isFineMode = fineMode
        return minutes != previousMinutes
    }

    /// Resolves the gesture when the mouse button is released.
    func end() -> Outcome {
        switch phase {
        case .pressed:
            return hasMovedBeyondClickSlop ? .cancel : .click
        case .pulling:
            return minutes > 0 ? .start(minutes: minutes) : .cancel
        case .cancelling:
            return .cancel
        }
    }

    /// Minute values that deserve a haptic "detent" as the user pulls past them.
    static func isDetent(_ minutes: Int) -> Bool {
        minutes > 0 && minutes % 5 == 0
    }

    private static func clampedMinutes(_ value: Int) -> Int {
        min(max(value, 1), PullTimerDurationCalculator.maximumMinutes)
    }
}
