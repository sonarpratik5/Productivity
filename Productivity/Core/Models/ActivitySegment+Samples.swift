import Foundation

#if DEBUG
extension ActivitySegment {
    static var sampleDay: [ActivitySegment] {
        sampleSegments(onDayOffset: 0, focusMinutes: 42, researchMinutes: 36, communicationMinutes: 21, entertainmentMinutes: 25)
    }

    static var sampleHistory: [ActivitySegment] {
        [
            sampleSegments(onDayOffset: -150, focusMinutes: 96, researchMinutes: 42, communicationMinutes: 28, entertainmentMinutes: 18),
            sampleSegments(onDayOffset: -126, focusMinutes: 74, researchMinutes: 34, communicationMinutes: 40, entertainmentMinutes: 36),
            sampleSegments(onDayOffset: -97, focusMinutes: 112, researchMinutes: 46, communicationMinutes: 18, entertainmentMinutes: 22),
            sampleSegments(onDayOffset: -70, focusMinutes: 88, researchMinutes: 52, communicationMinutes: 32, entertainmentMinutes: 30),
            sampleSegments(onDayOffset: -43, focusMinutes: 125, researchMinutes: 38, communicationMinutes: 24, entertainmentMinutes: 16),
            sampleSegments(onDayOffset: -25, focusMinutes: 62, researchMinutes: 28, communicationMinutes: 44, entertainmentMinutes: 48),
            sampleSegments(onDayOffset: -14, focusMinutes: 104, researchMinutes: 44, communicationMinutes: 20, entertainmentMinutes: 24),
            sampleSegments(onDayOffset: -7, focusMinutes: 80, researchMinutes: 36, communicationMinutes: 34, entertainmentMinutes: 34),
            sampleSegments(onDayOffset: -3, focusMinutes: 118, researchMinutes: 26, communicationMinutes: 22, entertainmentMinutes: 20),
            sampleSegments(onDayOffset: -2, focusMinutes: 92, researchMinutes: 48, communicationMinutes: 18, entertainmentMinutes: 26),
            sampleSegments(onDayOffset: -1, focusMinutes: 70, researchMinutes: 32, communicationMinutes: 36, entertainmentMinutes: 44),
            sampleDay
        ].flatMap { $0 }
    }

    private static func sampleSegments(
        onDayOffset dayOffset: Int,
        focusMinutes: Int,
        researchMinutes: Int,
        communicationMinutes: Int,
        entertainmentMinutes: Int
    ) -> [ActivitySegment] {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        let focusEnd = start.addingTimeInterval(TimeInterval(focusMinutes * 60))
        let researchStart = focusEnd.addingTimeInterval(12 * 60)
        let researchEnd = researchStart.addingTimeInterval(TimeInterval(researchMinutes * 60))
        let communicationStart = researchEnd.addingTimeInterval(18 * 60)
        let communicationEnd = communicationStart.addingTimeInterval(TimeInterval(communicationMinutes * 60))
        let entertainmentStart = communicationEnd.addingTimeInterval(16 * 60)
        let entertainmentEnd = entertainmentStart.addingTimeInterval(TimeInterval(entertainmentMinutes * 60))

        return [
            ActivitySegment(
                appName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode",
                title: "Development session",
                userDescription: "Building the timeline renderer",
                startDate: start,
                endDate: focusEnd,
                category: .focus,
                productivityScore: 1.0
            ),
            ActivitySegment(
                appName: "ChatGPT",
                bundleIdentifier: "com.openai.chat",
                title: "Research assistant",
                userDescription: "Architecture planning",
                startDate: researchStart,
                endDate: researchEnd,
                category: .research,
                productivityScore: 0.75
            ),
            ActivitySegment(
                appName: "Slack",
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                title: "Communication",
                startDate: communicationStart,
                endDate: communicationEnd,
                category: .communication,
                productivityScore: 0.55
            ),
            ActivitySegment(
                appName: "Browser",
                bundleIdentifier: "com.google.Chrome",
                title: "Web activity",
                startDate: entertainmentStart,
                endDate: entertainmentEnd,
                category: .entertainment,
                productivityScore: 0.1
            )
        ]
    }
}
#endif
