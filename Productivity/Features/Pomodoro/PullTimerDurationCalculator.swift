import Foundation
import CoreGraphics

/// Calculates natural minute durations, formatting, and target end times for pull-to-set timer interactions.
public struct PullTimerDurationCalculator: Sendable {
    public static let minimumDragThreshold: CGFloat = 12.0
    public static let maximumDragDistance: CGFloat = 520.0
    public static let maximumMinutes: Int = 180

    /// Calculates a natural number of minutes (1 to 180) based on vertical downward drag distance in points.
    ///
    /// - Parameter dragDistanceY: Vertical distance pulled downwards in points (>= 0).
    /// - Returns: Natural number of minutes (1, 2, 3... 180), or 0 if below minimum drag threshold.
    public static func calculateDuration(dragDistanceY: CGFloat) -> Int {
        guard dragDistanceY >= minimumDragThreshold else {
            return 0
        }

        let effectiveDrag = dragDistanceY - minimumDragThreshold

        // Progressive ergonomic scale:
        // 0..<45 pt   -> 1 to 5 min (1-minute steps)
        // 45..<160 pt  -> 5 to 25 min (1-minute steps)
        // 160..<320 pt -> 25 to 60 min (snapped to 5-minute increments)
        // 320..<520+ pt -> 60 to 180 min (snapped to 15-minute increments)
        let rawMinutes: Int
        if effectiveDrag < 45 {
            let step = effectiveDrag / 9.0
            rawMinutes = max(1, min(5, 1 + Int(step)))
        } else if effectiveDrag < 160 {
            let progress = (effectiveDrag - 45) / 115.0
            rawMinutes = 5 + Int(round(progress * 20.0))
        } else if effectiveDrag < 320 {
            let progress = (effectiveDrag - 160) / 160.0
            let stepFive = Int(round(progress * 7.0)) * 5
            rawMinutes = 25 + stepFive
        } else {
            let progress = min(1.0, (effectiveDrag - 320) / 200.0)
            let stepFifteen = Int(round(progress * 8.0)) * 15
            rawMinutes = 60 + stepFifteen
        }

        return min(max(1, rawMinutes), maximumMinutes)
    }

    /// Formats the duration into a clean natural language string (e.g. "15 minutes", "1 hour 30 min").
    public static func formattedDuration(minutes: Int) -> String {
        guard minutes > 0 else {
            return "Pull down to set timer"
        }

        if minutes < 60 {
            return "\(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        } else {
            return "\(hours) hr \(remainingMinutes) min"
        }
    }

    /// Returns a short label for compact badges (e.g. "25m", "1h 30m").
    public static func shortFormattedDuration(minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remaining = minutes % 60
        return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
    }

    /// Compact countdown shown next to the menu bar icon (e.g. "9:05", "24:59", "1:02:03").
    public static func menuBarCountdown(seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    /// Generates target completion time string (e.g. "Until 3:45 PM").
    public static func targetTimeString(
        minutes: Int,
        from referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard minutes > 0 else {
            return "Release to cancel"
        }
        let targetDate = calendar.date(byAdding: .minute, value: minutes, to: referenceDate)
            ?? referenceDate.addingTimeInterval(TimeInterval(minutes * 60))
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeStyle = .short
        return "Until \(formatter.string(from: targetDate))"
    }
}
