import Foundation

struct InsightSummary: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let value: String
    let trend: String
    let category: ActivityCategory
}

struct DailyActivityOverview {
    let date: Date
    let productiveTime: TimeInterval
    let unproductiveTime: TimeInterval
    let unknownTime: TimeInterval
    let totalTrackedTime: TimeInterval
    let segments: [ActivitySegment]

    var productivityRatio: Double {
        guard totalTrackedTime > 0 else { return 0 }
        return productiveTime / totalTrackedTime
    }
}
