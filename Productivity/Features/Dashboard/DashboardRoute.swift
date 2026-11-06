import Foundation

enum DashboardRoute: String, Hashable, CaseIterable {
    case today
    case insights
    case analytics
    case calendar
    case pomodoro
    case settings

    init?(widgetURL url: URL) {
        guard url.scheme == "focusgrove", let host = url.host else { return nil }
        switch host {
        case "today": self = .today
        case "board": self = .calendar
        case "pomodoro": self = .pomodoro
        case "insights": self = .insights
        case "analytics": self = .analytics
        default: return nil
        }
    }
}
