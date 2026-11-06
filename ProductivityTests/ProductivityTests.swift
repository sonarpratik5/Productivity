import Testing
@testable import Productivity
import Foundation

let activityLabelCatalogTestLock = NSLock()

private var userCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func userDate(
    _ day: Int,
    month: Int = 8,
    year: Int = 2026,
    hour: Int = 0,
    minute: Int = 0
) -> Date {
    userCalendar.date(from: DateComponents(
        timeZone: userCalendar.timeZone,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute
    ))!
}

private func userSegment(
    appName: String,
    bundleID: String,
    start: Date,
    end: Date,
    label: ActivityLabel,
    score: Double? = nil
) -> ActivitySegment {
    ActivitySegment(
        appName: appName,
        bundleIdentifier: bundleID,
        title: appName,
        startDate: start,
        endDate: end,
        category: label.category,
        label: label,
        productivityScore: score ?? label.productivityScore
    )
}

@Suite("RuleBasedActivityClassifier user rules")
struct RuleBasedActivityClassifierUserRuleTests {

    @Test("enabled user rule overrides built-in app classification")
    func enabledRuleOverridesBuiltInCategory() {
        let classifier = RuleBasedActivityClassifier(labelRules: [
            AppLabelRule(appName: "Spotify", bundleIdentifier: "com.spotify.client", label: .productive)
        ])

        #expect(classifier.label(for: "com.spotify.client", appName: "Spotify") == .productive)
        #expect(classifier.category(for: "com.spotify.client", appName: "Spotify") == .focus)
    }

    @Test("disabled user rule falls back to built-in classification")
    func disabledRuleFallsBackToBuiltInCategory() {
        let classifier = RuleBasedActivityClassifier(labelRules: [
            AppLabelRule(appName: "Spotify", bundleIdentifier: "com.spotify.client", label: .productive, isEnabled: false)
        ])

        #expect(classifier.label(for: "com.spotify.client", appName: "Spotify") == .unproductive)
        #expect(classifier.category(for: "com.spotify.client", appName: "Spotify") == .entertainment)
    }

    @Test("app-name matching is case-insensitive for renamed apps")
    func appNameMatchingIsCaseInsensitive() {
        let classifier = RuleBasedActivityClassifier(labelRules: [
            AppLabelRule(appName: "Research Browser", bundleIdentifier: "com.example.research", label: .productive)
        ])

        #expect(classifier.label(for: "com.example.unknown", appName: "MY RESEARCH BROWSER") == .productive)
    }

    @Test("this app stays focus even if a persisted rule says otherwise")
    func ownBundleIdentifierAlwaysFocus() {
        let classifier = RuleBasedActivityClassifier(
            labelRules: [
                AppLabelRule(appName: "Productivity", bundleIdentifier: "me.productivity", label: .unproductive)
            ],
            selfBundleIdentifier: "me.productivity"
        )

        #expect(classifier.label(for: "me.productivity", appName: "Productivity") == .focus)
    }
}

@Suite("ManualActivityEvent human schedules")
struct ManualActivityEventHumanScheduleTests {

    @Test("weekday recurrence creates only Monday through Friday segments")
    func weekdaysSkipWeekend() {
        let event = ManualActivityEvent(
            title: "Work block",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            label: .focus,
            recurrence: .weekdays
        )
        let interval = DateInterval(start: userDate(24), end: userDate(31))

        let segments = event.segments(in: interval, calendar: userCalendar)

        #expect(segments.count == 5)
        #expect(segments.map { userCalendar.component(.weekday, from: $0.startDate) } == [2, 3, 4, 5, 6])
        #expect(segments.allSatisfy { abs($0.duration - 3600) < 0.001 })
    }

    @Test("custom weekly recurrence honors selected weekdays")
    func customWeeklyUsesWeekdayMask() {
        let event = ManualActivityEvent(
            title: "Gym",
            startDate: userDate(24, hour: 18),
            endDate: userDate(24, hour: 19),
            label: .health,
            recurrence: .customWeekly,
            weekdayMask: [3, 5]
        )
        let interval = DateInterval(start: userDate(24), end: userDate(31))

        let segments = event.segments(in: interval, calendar: userCalendar)

        #expect(segments.count == 2)
        #expect(segments.map { userCalendar.component(.weekday, from: $0.startDate) } == [3, 5])
        #expect(segments.allSatisfy { $0.label == .health })
    }

    @Test("daily overnight event contributes both carried and same-day sleep")
    func dailyOvernightEventClipsIntoVisibleDay() {
        let event = ManualActivityEvent(
            title: "Sleep",
            startDate: userDate(24, hour: 22),
            endDate: userDate(24, hour: 6),
            label: .sleep,
            isSleep: true,
            recurrence: .daily
        )
        let tuesday = DateInterval(start: userDate(25), end: userDate(26))

        let segments = event.segments(in: tuesday, calendar: userCalendar)

        #expect(segments.count == 2)
        #expect(segments[0].startDate == userDate(25))
        #expect(segments[0].endDate == userDate(25, hour: 6))
        #expect(segments[1].startDate == userDate(25, hour: 22))
        #expect(segments[1].endDate == userDate(26))
        #expect(segments.allSatisfy { $0.isSleepEvent })
    }

    @Test("upcoming alerts skip past occurrences and apply alert offset")
    func notificationDatesUseOffsetAndFutureFilter() {
        let event = ManualActivityEvent(
            title: "Standup",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 30),
            label: .productive,
            recurrence: .daily,
            alert: .fifteenMinutesBefore
        )

        let dates = event.upcomingNotificationDates(
            from: userDate(24, hour: 8),
            calendar: userCalendar,
            limit: 2
        )

        #expect(dates == [
            userDate(24, hour: 8, minute: 45),
            userDate(25, hour: 8, minute: 45)
        ])
    }

    @Test("reschedule returns noUpcomingDates for past one-time events")
    func rescheduleReturnsNoUpcomingDatesForPastEvent() async {
        let pastDate = Date(timeIntervalSinceNow: -3600)
        let event = ManualActivityEvent(
            title: "Past Meeting",
            startDate: pastDate,
            endDate: pastDate.addingTimeInterval(1800),
            label: .productive,
            recurrence: .none,
            alert: .atStart
        )
        let dates = event.upcomingNotificationDates(from: Date(), limit: 32)
        #expect(dates.isEmpty)
    }
}

@Suite("InsightEngine sleep accounting")
struct InsightEngineSleepAccountingTests {

    @Test("sleep event time is subtracted from overlapping tracked activity")
    func sleepEventTimeIsSubtractedFromTrackedActivity() {
        let segments = [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 11),
                label: .focus
            ),
            userSegment(
                appName: "Sleep",
                bundleID: "manual.event.sleep.bedtime",
                start: userDate(24, hour: 10),
                end: userDate(24, hour: 11),
                label: .sleep
            )
        ]

        let overview = InsightEngine().dailyOverview(
            from: segments,
            on: userDate(24, hour: 12)
        )

        #expect(abs(overview.totalTrackedTime - 3600) < 0.001)
        #expect(abs(overview.productiveTime - 3600) < 0.001)
        #expect(abs(overview.productivityRatio - 1.0) < 0.001)
    }

    @Test("overlapping sleep events are only subtracted once")
    func overlappingSleepEventsAreOnlySubtractedOnce() {
        let segments = [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 12),
                label: .focus
            ),
            userSegment(
                appName: "Sleep",
                bundleID: "manual.event.sleep.bedtime",
                start: userDate(24, hour: 10),
                end: userDate(24, hour: 11),
                label: .sleep
            ),
            userSegment(
                appName: "Nap",
                bundleID: "manual.event.sleep.nap",
                start: userDate(24, hour: 10, minute: 30),
                end: userDate(24, hour: 11, minute: 30),
                label: .sleep
            )
        ]

        let overview = InsightEngine().dailyOverview(
            from: segments,
            on: userDate(24, hour: 12)
        )

        #expect(abs(overview.totalTrackedTime - 5_400) < 0.001)
        #expect(abs(overview.productiveTime - 5_400) < 0.001)
    }
}

@Suite("Backup decoding compatibility")
struct BackupDecodingCompatibilityTests {

    @Test("activity segment backups without labels derive labels from category")
    @MainActor
    func activitySegmentWithoutLabelDerivesFallbackLabel() throws {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let json = """
        {
          "id": "\(id.uuidString)",
          "appName": "Xcode",
          "bundleIdentifier": "com.apple.dt.Xcode",
          "title": "Xcode",
          "startDate": 0,
          "endDate": 3600,
          "category": "focus",
          "productivityScore": 1.0
        }
        """.data(using: .utf8)!

        let segment = try JSONDecoder().decode(ActivitySegment.self, from: json)

        #expect(segment.label == .focus)
        #expect(segment.category == .focus)
    }

    @Test("older preference backups receive default optional fields")
    @MainActor
    func olderPreferenceBackupDefaultsMissingFields() throws {
        let json = """
        {
          "appearance": "system",
          "theme": "amethyst",
          "displayName": "Pratik",
          "isTrackingEnabled": true,
          "appTrackingMode": "all",
          "snapshotIntervalSeconds": 15,
          "idleTimeoutSeconds": 300,
          "visibleCompanionWindowSeconds": 180,
          "timelineHorizonSeconds": 86400,
          "isTimelineEventContextOverlayEnabled": true,
          "isSleepHiddenInDayProgress": true,
          "isPomodoroSoundEnabled": true,
          "isDailyFocusHeaderEnabled": true,
          "customMotivationQuote": ""
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(ProductivityPreferenceBackup.self, from: json)

        #expect(preferences.textSize == AppTextSize.standard.rawValue)
        #expect(preferences.pomodoroFocusStartSound == PomodoroSoundEvent.focusStart.defaultSound.rawValue)
        #expect(preferences.pomodoroShortBreakStartSound == PomodoroSoundEvent.shortBreakStart.defaultSound.rawValue)
        #expect(preferences.pomodoroLongBreakStartSound == PomodoroSoundEvent.longBreakStart.defaultSound.rawValue)
        #expect(preferences.pomodoroCompletionSound == PomodoroSoundEvent.completion.defaultSound.rawValue)
        #expect(preferences.productivityThresholdPercent == 70)
    }
}

@Suite("AdvancedAnalyticsEngine human rollups")
struct AdvancedAnalyticsEngineHumanRollupTests {

    @Test("analytics excludes sleep and lifecycle context from tracked totals")
    func analyticsExcludesNonUserAttentionContext() {
        let segments = [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 10),
                label: .focus
            ),
            userSegment(
                appName: "Sleep",
                bundleID: "manual.event.sleep.1",
                start: userDate(24, hour: 0),
                end: userDate(24, hour: 8),
                label: .sleep
            ),
            userSegment(
                appName: "Opened",
                bundleID: "productivity.lifecycle.opened",
                start: userDate(24, hour: 8),
                end: userDate(24, hour: 9),
                label: .unknown
            )
        ]

        let snapshot = AdvancedAnalyticsEngine().snapshot(
            from: segments,
            range: .last14Days,
            referenceDate: userDate(24, hour: 12),
            calendar: userCalendar
        )

        #expect(abs(snapshot.totalTrackedTime - 3600) < 0.001)
        #expect(abs(snapshot.productiveTime - 3600) < 0.001)
        #expect(snapshot.topApps.map(\.bundleIdentifier) == ["com.apple.dt.Xcode"])
    }

    @Test("overlapping apps are reduced to primary attention before ratio calculation")
    func analyticsUsesPrimaryAttentionForOverlappingApps() {
        let segments = [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 10),
                label: .focus,
                score: 1.0
            ),
            userSegment(
                appName: "Video",
                bundleID: "org.videolan.vlc",
                start: userDate(24, hour: 9, minute: 30),
                end: userDate(24, hour: 10, minute: 30),
                label: .unproductive,
                score: 0.05
            )
        ]

        let snapshot = AdvancedAnalyticsEngine().snapshot(
            from: segments,
            range: .last14Days,
            referenceDate: userDate(24, hour: 12),
            calendar: userCalendar
        )

        #expect(abs(snapshot.totalTrackedTime - 5400) < 0.001)
        #expect(abs(snapshot.productiveTime - 3600) < 0.001)
        #expect(abs(snapshot.unproductiveTime - 1800) < 0.001)
        #expect(abs(snapshot.productiveRatio - (2.0 / 3.0)) < 0.001)
        #expect(snapshot.contextSwitchCount == 1)
    }

    @Test("custom productive labels stay visible in analytics breakdown")
    @MainActor
    func customProductiveLabelsStayVisibleInAnalyticsBreakdown() {
        activityLabelCatalogTestLock.lock()
        let previousDefinitions = ActivityLabelCatalog.customDefinitions()
        let customLabel = ActivityLabel.custom("custom.test.deep-work.analytics")
        ActivityLabelCatalog.saveCustomDefinitions([
            ActivityLabelDefinition(
                id: customLabel.id,
                title: "Deep Work",
                systemImage: "scope",
                tint: ActivityLabelColor(red: 0.2, green: 0.7, blue: 0.6),
                rollup: .productive
            )
        ])
        defer {
            ActivityLabelCatalog.saveCustomDefinitions(previousDefinitions)
            activityLabelCatalogTestLock.unlock()
        }

        let segments = [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 10),
                label: customLabel
            )
        ]

        let snapshot = AdvancedAnalyticsEngine().snapshot(
            from: segments,
            range: .last14Days,
            referenceDate: userDate(24, hour: 12),
            calendar: userCalendar
        )

        let customLabelBreakdown = snapshot.labelBreakdown.first { entry in entry.key.id == customLabel.id }?.value
        #expect(customLabelBreakdown == 3_600)
        #expect(snapshot.productiveTime == 3_600)
        #expect(snapshot.productiveRatio == 1)
    }

    @Test("hour ranking preserves duration tie breakers")
    func hourRankingPreservesDurationTieBreakers() {
        let segments = [
            userSegment(
                appName: "Research",
                bundleID: "com.example.research",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 9, minute: 40),
                label: .productive
            ),
            userSegment(
                appName: "Writing",
                bundleID: "com.example.writing",
                start: userDate(24, hour: 10),
                end: userDate(24, hour: 11),
                label: .productive
            ),
            userSegment(
                appName: "Social",
                bundleID: "com.example.social",
                start: userDate(24, hour: 14),
                end: userDate(24, hour: 14, minute: 50),
                label: .unproductive
            ),
            userSegment(
                appName: "Video",
                bundleID: "com.example.video",
                start: userDate(24, hour: 15),
                end: userDate(24, hour: 15, minute: 30),
                label: .unproductive
            )
        ]

        let snapshot = AdvancedAnalyticsEngine().snapshot(
            from: segments,
            range: .last14Days,
            referenceDate: userDate(24, hour: 18),
            calendar: userCalendar
        )

        #expect(snapshot.peakFocusHour?.hour == 10)
        #expect(snapshot.weakestFocusHour?.hour == 15)
    }

}

@Suite("Pomodoro configuration robustness")
struct PomodoroConfigurationRobustnessTests {

    @Test("configuration initializer clamps invalid values to supported ranges")
    func initializerClampsInvalidValues() {
        let configuration = PomodoroConfiguration(
            focusMinutes: -10,
            shortBreakMinutes: 0,
            longBreakMinutes: 999,
            sessionsBeforeLongBreak: 0
        )

        #expect(configuration.focusMinutes == PomodoroConfiguration.focusMinutesRange.lowerBound)
        #expect(configuration.shortBreakMinutes == PomodoroConfiguration.shortBreakMinutesRange.lowerBound)
        #expect(configuration.longBreakMinutes == PomodoroConfiguration.longBreakMinutesRange.upperBound)
        #expect(configuration.sessionsBeforeLongBreak == PomodoroConfiguration.sessionsBeforeLongBreakRange.lowerBound)
    }

    @Test("decoded configuration is normalized before use")
    func decodedConfigurationIsNormalized() throws {
        let json = """
        {
          "focusMinutes": -1,
          "shortBreakMinutes": 200,
          "longBreakMinutes": 0,
          "sessionsBeforeLongBreak": -4
        }
        """.data(using: .utf8)!

        let configuration = try JSONDecoder().decode(PomodoroConfiguration.self, from: json)

        #expect(configuration.focusMinutes == PomodoroConfiguration.focusMinutesRange.lowerBound)
        #expect(configuration.shortBreakMinutes == PomodoroConfiguration.shortBreakMinutesRange.upperBound)
        #expect(configuration.longBreakMinutes == PomodoroConfiguration.longBreakMinutesRange.lowerBound)
        #expect(configuration.sessionsBeforeLongBreak == PomodoroConfiguration.sessionsBeforeLongBreakRange.lowerBound)
    }

    @Test("view model normalizes mutated configuration before persisting")
    @MainActor
    func viewModelNormalizesMutatedConfiguration() {
        let defaults = UserDefaults.standard
        let keys = [
            PomodoroPreferenceKeys.focusMinutes,
            PomodoroPreferenceKeys.shortBreakMinutes,
            PomodoroPreferenceKeys.longBreakMinutes,
            PomodoroPreferenceKeys.sessionsBeforeLongBreak
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for key in keys {
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        let viewModel = PomodoroViewModel(configuration: PomodoroConfiguration(
            focusMinutes: 25,
            shortBreakMinutes: 5,
            longBreakMinutes: 15,
            sessionsBeforeLongBreak: 4
        ))

        viewModel.configuration.focusMinutes = 10_000
        viewModel.configuration.sessionsBeforeLongBreak = -2

        #expect(viewModel.configuration.focusMinutes == PomodoroConfiguration.focusMinutesRange.upperBound)
        #expect(viewModel.configuration.sessionsBeforeLongBreak == PomodoroConfiguration.sessionsBeforeLongBreakRange.lowerBound)
    }
}

@Suite("ActivityRepository contracts")
struct ActivityRepositoryContractTests {

    @Test("in-memory repository defaults to empty")
    @MainActor
    func inMemoryRepositoryDefaultsToEmpty() async throws {
        let repository = InMemoryActivityRepository()

        let segments = try await repository.allSegments()

        #expect(segments.isEmpty)
    }

    @Test("in-memory repository upserts live segment snapshots by ID")
    @MainActor
    func inMemoryRepositoryUpsertsBySegmentID() async throws {
        let segmentID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let firstSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 15),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let laterSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = InMemoryActivityRepository(segments: [])

        try await repository.save([firstSnapshot])
        try await repository.save([laterSnapshot])
        let segments = try await repository.allSegments()

        #expect(segments == [laterSnapshot])
    }

    @Test("file-backed repository replays unflushed WAL on startup")
    @MainActor
    func fileBackedRepositoryReplaysUnflushedWAL() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-wal")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let segment = ActivitySegment(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 23, minute: 30),
            endDate: userDate(25, hour: 0, minute: 30),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        try await repository.save([segment])
        let restartedRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let recoveredSegments = try await restartedRepository.allSegments()

        #expect(recoveredSegments == [segment])

        try await repository.flush()
        try await restartedRepository.flush()
    }

    @Test("file-backed repository stores multi-day segments in every overlapping day bucket")
    @MainActor
    func fileBackedRepositoryFindsMultiDaySegmentsFromLaterDayQueries() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-multiday")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let segment = ActivitySegment(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            appName: "Sleep",
            bundleIdentifier: "productivity.lifecycle.sleep",
            title: "Away",
            startDate: userDate(24, hour: 22),
            endDate: userDate(27, hour: 6),
            category: .system,
            label: .sleep,
            productivityScore: 0
        )
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        try await repository.save([segment])
        try await repository.flush()

        let restartedRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let laterDaySegments = try await restartedRepository.segments(
            for: DateInterval(start: userDate(26), end: userDate(27))
        )
        let allSegments = try await restartedRepository.allSegments()

        #expect(laterDaySegments == [segment])
        #expect(allSegments == [segment])
    }

    @Test("file-backed repository removes empty day files after deleting their final segment")
    @MainActor
    func fileBackedRepositoryRemovesEmptyDayFilesAfterDelete() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-empty-bucket")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let segment = ActivitySegment(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let dayFile = rootDirectory
            .appendingPathComponent("2026-08-24", isDirectory: false)
            .appendingPathExtension("activitysegments")
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        try await repository.save([segment])
        try await repository.flush()
        #expect(FileManager.default.fileExists(atPath: dayFile.path))

        try await repository.deleteSegments(identifiedBy: [segment.id])

        #expect(!FileManager.default.fileExists(atPath: dayFile.path))
        #expect(try await repository.allSegments().isEmpty)
    }

    @Test("file-backed repository tolerates duplicate IDs in a persisted day file")
    @MainActor
    func fileBackedRepositoryDeduplicatesPersistedDayFiles() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-duplicate-id")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let segmentID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let firstSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 15),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let laterSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let data = try encoder.encode([firstSnapshot, laterSnapshot])
        try data.write(
            to: rootDirectory
                .appendingPathComponent("2026-08-24", isDirectory: false)
                .appendingPathExtension("activitysegments")
        )
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let segments = try await repository.allSegments()

        #expect(segments == [laterSnapshot])
    }

    @Test("file-backed repository quarantines corrupt day files and keeps loading healthy days")
    @MainActor
    func fileBackedRepositoryQuarantinesCorruptDayFiles() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-corrupt-day")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let healthySegment = ActivitySegment(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(25, hour: 9),
            endDate: userDate(25, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([healthySegment]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-25", isDirectory: false)
                .appendingPathExtension("activitysegments")
        )
        let corruptDayFile = rootDirectory
            .appendingPathComponent("2026-08-24", isDirectory: false)
            .appendingPathExtension("activitysegments")
        try Data("not a property list".utf8).write(to: corruptDayFile)
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let segments = try await repository.allSegments()
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)

        #expect(segments == [healthySegment])
        #expect(!FileManager.default.fileExists(atPath: corruptDayFile.path))
        #expect(remainingFiles.contains { $0.hasPrefix("2026-08-24.activitysegments.corrupt-") })
    }

    @Test("file-backed repository full-day query does not load exclusive end day")
    @MainActor
    func fileBackedRepositoryFullDayQuerySkipsExclusiveEndDayFile() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-exclusive-end-day")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let segment = ActivitySegment(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([segment]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-24", isDirectory: false)
                .appendingPathExtension("activitysegments")
        )
        let exclusiveEndDayFile = rootDirectory
            .appendingPathComponent("2026-08-25", isDirectory: false)
            .appendingPathExtension("activitysegments")
        try Data("not a property list".utf8).write(to: exclusiveEndDayFile)
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let segments = try await repository.segments(for: DateInterval(start: userDate(24), end: userDate(25)))
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)

        #expect(segments == [segment])
        #expect(FileManager.default.fileExists(atPath: exclusiveEndDayFile.path))
        #expect(!remainingFiles.contains { $0.hasPrefix("2026-08-25.activitysegments.corrupt-") })
    }

    @Test("file-backed repository cleans old day buckets for unindexed upserts")
    @MainActor
    func fileBackedRepositoryCleansOldDayBucketsForUnindexedUpserts() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-unindexed-upsert")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let segmentID = UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!
        let originalSegment = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 23),
            endDate: userDate(25, hour: 1),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let movedSegment = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(26, hour: 9),
            endDate: userDate(26, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let originalRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        try await originalRepository.save([originalSegment])
        try await originalRepository.flush()

        let restartedRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        try await restartedRepository.save([movedSegment])
        try await restartedRepository.flush()

        #expect(try await restartedRepository.segments(for: DateInterval(start: userDate(24), end: userDate(25))).isEmpty)
        #expect(try await restartedRepository.segments(for: DateInterval(start: userDate(25), end: userDate(26))).isEmpty)
        #expect(try await restartedRepository.allSegments() == [movedSegment])
    }

    @Test("file-backed repository ignores shorter stale snapshots by ID")
    @MainActor
    func fileBackedRepositoryIgnoresShorterStaleSnapshotsByID() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-shorter-snapshot")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let segmentID = UUID(uuidString: "ACACACAC-ACAC-ACAC-ACAC-ACACACACACAC")!
        let longerSegment = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let shorterSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 15),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        try await repository.save([longerSegment])
        try await repository.save([shorterSnapshot])
        try await repository.flush()

        #expect(try await repository.allSegments() == [longerSegment])
    }

    @Test("file-backed repository reuses persisted segment index during new saves")
    @MainActor
    func fileBackedRepositoryReusesPersistedSegmentIndexDuringNewSaves() async throws {
        let rootDirectory = temporaryTestDirectory(named: "activity-persisted-index")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let existingSegment = ActivitySegment(
            id: UUID(uuidString: "ADADADAD-ADAD-ADAD-ADAD-ADADADADADAD")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let newSegment = ActivitySegment(
            id: UUID(uuidString: "AEAEAEAE-AEAE-AEAE-AEAE-AEAEAEAEAEAE")!,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            title: "Safari",
            startDate: userDate(26, hour: 11),
            endDate: userDate(26, hour: 12),
            category: .research,
            label: .productive,
            productivityScore: 0.8
        )
        let originalRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        try await originalRepository.save([existingSegment])
        try await originalRepository.flush()
        _ = try await originalRepository.allSegments()

        let corruptUnrelatedDayFile = rootDirectory
            .appendingPathComponent("2026-08-25", isDirectory: false)
            .appendingPathExtension("activitysegments")
        try Data("not a property list".utf8).write(to: corruptUnrelatedDayFile)

        let restartedRepository = FileBackedActivityRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        try await restartedRepository.save([newSegment])
        try await restartedRepository.flush()

        #expect(FileManager.default.fileExists(atPath: corruptUnrelatedDayFile.path))
        #expect(try await restartedRepository.segments(for: DateInterval(start: userDate(26), end: userDate(27))) == [newSegment])
    }
}

@Suite("SQLiteActivityRepository contracts")
struct SQLiteActivityRepositoryContractTests {

    @Test("SQLite repository persists and reloads bounded range queries")
    @MainActor
    func sqliteRepositoryPersistsRangeQueries() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-range")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let segment = ActivitySegment(
            id: UUID(uuidString: "B0B0B0B0-B0B0-B0B0-B0B0-B0B0B0B0B0B0")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 23, minute: 30),
            endDate: userDate(25, hour: 0, minute: 30),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        try await repository.save([segment])
        let restartedRepository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        #expect(try await restartedRepository.segments(for: DateInterval(start: userDate(25), end: userDate(26))) == [segment])
        #expect(try await restartedRepository.allSegments() == [segment])
    }

    @Test("SQLite repository ignores shorter stale snapshots by ID")
    @MainActor
    func sqliteRepositoryIgnoresShorterStaleSnapshotsByID() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-stale")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let segmentID = UUID(uuidString: "B1B1B1B1-B1B1-B1B1-B1B1-B1B1B1B1B1B1")!
        let longerSegment = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let shorterSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 15),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        try await repository.save([longerSegment])
        try await repository.save([shorterSnapshot])

        #expect(try await repository.allSegments() == [longerSegment])
    }

    @Test("SQLite repository deletes segments by ID")
    @MainActor
    func sqliteRepositoryDeletesSegmentsByID() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-delete-by-id")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let segmentA = ActivitySegment(
            id: UUID(uuidString: "C0C0C0C0-C0C0-C0C0-C0C0-C0C0C0C0C0C0")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let segmentB = ActivitySegment(
            id: UUID(uuidString: "C1C1C1C1-C1C1-C1C1-C1C1-C1C1C1C1C1C1")!,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            title: "Safari",
            startDate: userDate(24, hour: 11),
            endDate: userDate(24, hour: 12),
            category: .research,
            label: .productive,
            productivityScore: 0.8
        )
        let repository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        try await repository.save([segmentA, segmentB])
        try await repository.deleteSegments(identifiedBy: [segmentA.id])
        let remaining = try await repository.allSegments()

        #expect(remaining == [segmentB])
    }

    @Test("SQLite repository deletes all segments")
    @MainActor
    func sqliteRepositoryDeletesAllSegments() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-delete-all")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let segment = ActivitySegment(
            id: UUID(uuidString: "C2C2C2C2-C2C2-C2C2-C2C2-C2C2C2C2C2C2")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        try await repository.save([segment])
        try await repository.deleteAllSegments()
        let remaining = try await repository.allSegments()

        #expect(remaining.isEmpty)
    }

    @Test("SQLite repository flush WAL checkpoint completes without error")
    @MainActor
    func sqliteRepositoryFlushCompletesWithoutError() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-flush")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedActivityRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let segment = ActivitySegment(
            id: UUID(uuidString: "C3C3C3C3-C3C3-C3C3-C3C3-C3C3C3C3C3C3")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )

        try await repository.save([segment])
        try await repository.flush()
        let reloaded = try await SQLiteBackedActivityRepository(
            databaseURL: databaseURL,
            legacyRootDirectory: nil,
            calendar: userCalendar,
            migratesLegacyStore: false
        ).allSegments()

        #expect(reloaded == [segment])
    }

    @Test("SQLite repository migrates legacy file-backed activity once")
    @MainActor
    func sqliteRepositoryMigratesLegacyActivity() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-activity-migration")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let legacyRootDirectory = rootDirectory.appendingPathComponent("ActivitySegments", isDirectory: true)
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let legacySegment = ActivitySegment(
            id: UUID(uuidString: "B2B2B2B2-B2B2-B2B2-B2B2-B2B2B2B2B2B2")!,
            appName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            title: "Research",
            startDate: userDate(24, hour: 11),
            endDate: userDate(24, hour: 12),
            category: .research,
            label: .productive,
            productivityScore: 0.8
        )
        let legacyRepository = FileBackedActivityRepository(rootDirectory: legacyRootDirectory, calendar: userCalendar)
        try await legacyRepository.save([legacySegment])
        try await legacyRepository.flush()

        let repository = SQLiteBackedActivityRepository(
            databaseURL: databaseURL,
            legacyRootDirectory: legacyRootDirectory,
            calendar: userCalendar
        )

        #expect(try await repository.allSegments() == [legacySegment])
    }
}

@Suite("ActivityCSVExporter")
struct ActivityCSVExporterTests {

    @Test("productivity scores use POSIX decimal formatting")
    func productivityScoresUsePOSIXDecimalFormatting() {
        let document = ActivityCSVExporter.document(for: [
            userSegment(
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                start: userDate(24, hour: 9),
                end: userDate(24, hour: 10),
                label: .focus,
                score: 0.75
            )
        ])

        #expect(document.text.contains("\"0.75\""))
        #expect(!document.text.contains("\"0,75\""))
    }
}

@Suite("DashboardViewModel persistence")
struct DashboardViewModelPersistenceTests {

    @Test("mock tracker defaults to empty")
    @MainActor
    func mockTrackerDefaultsToEmpty() async {
        let tracker = MockActivityTracker()

        var snapshots: [[ActivitySegment]] = []
        for await segments in tracker.activitySegments {
            snapshots.append(segments)
        }

        #expect(tracker.currentSegments.isEmpty)
        #expect(!tracker.isCapturingLiveActivity)
        #expect(snapshots == [[]])
    }

    @Test("live tracking persists only changed segment snapshots")
    @MainActor
    func liveTrackingPersistsOnlyChangedSnapshots() async throws {
        let segmentID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let firstSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 15),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let extendedSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 9, minute: 30),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let repository = RecordingActivityRepository()
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: [
                [firstSnapshot],
                [firstSnapshot],
                [extendedSnapshot]
            ]),
            insightEngine: InsightEngine(),
            activityRepository: repository,
            timelineLabelRepository: InMemoryTimelineLabelRepository()
        )

        await viewModel.startTracking()
        let savedBatches = repository.savedBatchesSnapshot()

        #expect(savedBatches == [[firstSnapshot], [extendedSnapshot]])
    }

    @Test("duplicate live snapshots skip dashboard recomputation while changed snapshots still update")
    @MainActor
    func duplicateLiveSnapshotsSkipDashboardRecomputationWhileChangedSnapshotsStillUpdate() async throws {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let segmentID = UUID(uuidString: "34343434-3434-3434-3434-343434343434")!
        let firstSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: todayStart,
            endDate: todayStart.addingTimeInterval(15 * 60),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let extendedSnapshot = ActivitySegment(
            id: segmentID,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: todayStart,
            endDate: todayStart.addingTimeInterval(30 * 60),
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let insightEngine = CountingInsightEngine()
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: [
                [firstSnapshot],
                [firstSnapshot],
                [extendedSnapshot]
            ]),
            insightEngine: insightEngine,
            activityRepository: RecordingActivityRepository(),
            timelineLabelRepository: InMemoryTimelineLabelRepository()
        )

        await viewModel.startTracking()

        #expect(insightEngine.dailyOverviewCallCount == 4)
        #expect(viewModel.overview.totalTrackedTime == 30 * 60)
    }

    @Test("startup load feeds dashboard, insights, and analytics metric segments")
    @MainActor
    func startupLoadFeedsDashboardInsightsAndAnalytics() async throws {
        let todayStart = Calendar.current.startOfDay(for: Date())
        let segmentStart = todayStart
        let segmentEnd = Calendar.current.date(byAdding: .hour, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(3_600)
        let trackedSegment = ActivitySegment(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: segmentStart,
            endDate: segmentEnd,
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let labelOverride = TimelineLabelSegment(
            label: .unproductive,
            startDate: segmentStart,
            endDate: segmentEnd
        )
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: []),
            insightEngine: InsightEngine(),
            activityRepository: InMemoryActivityRepository(segments: [trackedSegment]),
            timelineLabelRepository: InMemoryTimelineLabelRepository(segments: [labelOverride])
        )

        await viewModel.loadPersistedSegmentsIfNeeded()
        let analyticsSnapshot = AdvancedAnalyticsEngine().snapshot(
            from: viewModel.insightMetricSegments,
            range: .last14Days,
            referenceDate: segmentEnd,
            calendar: Calendar.current
        )

        #expect(viewModel.overview.segments.contains(trackedSegment))
        #expect(viewModel.insightSegments.contains(trackedSegment))
        #expect(viewModel.todayMetricSegments.contains { $0.id == trackedSegment.id && $0.label == .unproductive })
        #expect(viewModel.insightMetricSegments.contains { $0.id == trackedSegment.id && $0.label == .unproductive })
        #expect(viewModel.overview.unproductiveTime >= 3_600)
        let unproductiveBreakdown = analyticsSnapshot.labelBreakdown.first { entry in entry.key.id == ActivityLabel.unproductive.id }?.value
        #expect(unproductiveBreakdown == 3_600)
    }

    @Test("historical insight interval loads older local storage and label overlays")
    @MainActor
    func historicalInsightIntervalLoadsOlderLocalStorageAndLabels() async throws {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        let olderStart = calendar.date(from: DateComponents(year: currentYear - 1, month: 3, day: 12, hour: 9))!
        let olderEnd = calendar.date(byAdding: .hour, value: 1, to: olderStart)!
        let olderSegment = ActivitySegment(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            appName: "Xcode",
            bundleIdentifier: "com.apple.dt.Xcode",
            title: "Xcode",
            startDate: olderStart,
            endDate: olderEnd,
            category: .focus,
            label: .focus,
            productivityScore: 1
        )
        let olderLabelOverride = TimelineLabelSegment(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            label: .unproductive,
            startDate: olderStart,
            endDate: olderEnd
        )
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: []),
            insightEngine: InsightEngine(),
            activityRepository: InMemoryActivityRepository(segments: [olderSegment]),
            timelineLabelRepository: InMemoryTimelineLabelRepository(segments: [olderLabelOverride])
        )

        await viewModel.loadPersistedSegmentsIfNeeded()
        #expect(!viewModel.insightSegments.contains(olderSegment))

        await viewModel.loadInsightData(for: DateInterval(start: olderStart, end: olderEnd))

        #expect(viewModel.insightSegments.contains(olderSegment))
        #expect(viewModel.insightMetricSegments.contains {
            $0.id == olderSegment.id
                && $0.label == .unproductive
                && $0.startDate == olderStart
                && $0.endDate == olderEnd
        })

        await viewModel.reloadPersistedSegments()

        #expect(viewModel.insightSegments.contains(olderSegment))
        #expect(viewModel.insightMetricSegments.contains {
            $0.id == olderSegment.id
                && $0.label == .unproductive
                && $0.startDate == olderStart
                && $0.endDate == olderEnd
        })
    }

    @Test("editing today's labels preserves adjacent previous-day labels in UI state")
    @MainActor
    func editingTodayLabelsPreservesAdjacentPreviousDayLabels() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86_400)
        let labelStart = calendar.date(byAdding: .hour, value: 9, to: todayStart) ?? todayStart.addingTimeInterval(32_400)
        let labelEnd = calendar.date(byAdding: .hour, value: 10, to: todayStart) ?? labelStart.addingTimeInterval(3_600)
        let previousDayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            label: .productive,
            startDate: yesterdayStart,
            endDate: todayStart
        )
        let todayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            label: .unproductive,
            startDate: labelStart,
            endDate: labelEnd
        )
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: []),
            insightEngine: InsightEngine(),
            activityRepository: InMemoryActivityRepository(segments: []),
            timelineLabelRepository: InMemoryTimelineLabelRepository(segments: [previousDayLabel])
        )

        await viewModel.loadPersistedSegmentsIfNeeded()
        viewModel.updateLabelSegments([todayLabel])

        #expect(viewModel.labelSegments.contains(previousDayLabel))
        #expect(viewModel.labelSegments.contains {
            $0.label == todayLabel.label
                && $0.startDate == todayLabel.startDate
                && $0.endDate == todayLabel.endDate
        })
    }

    @Test("editing today's labels preserves previous-day portion of spanning label in UI state")
    @MainActor
    func editingTodayLabelsPreservesPreviousDayPortionOfSpanningLabel() async throws {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86_400)
        let spanningStart = calendar.date(byAdding: .hour, value: 23, to: yesterdayStart) ?? todayStart.addingTimeInterval(-3_600)
        let spanningEnd = calendar.date(byAdding: .hour, value: 2, to: todayStart) ?? todayStart.addingTimeInterval(7_200)
        let replacementStart = calendar.date(byAdding: .hour, value: 9, to: todayStart) ?? todayStart.addingTimeInterval(32_400)
        let replacementEnd = calendar.date(byAdding: .hour, value: 10, to: todayStart) ?? replacementStart.addingTimeInterval(3_600)
        let spanningLabel = TimelineLabelSegment(
            id: UUID(uuidString: "89898989-8989-8989-8989-898989898989")!,
            label: .productive,
            startDate: spanningStart,
            endDate: spanningEnd
        )
        let todayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "98989898-9898-9898-9898-989898989898")!,
            label: .unproductive,
            startDate: replacementStart,
            endDate: replacementEnd
        )
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: []),
            insightEngine: InsightEngine(),
            activityRepository: InMemoryActivityRepository(segments: []),
            timelineLabelRepository: InMemoryTimelineLabelRepository(segments: [spanningLabel])
        )

        await viewModel.loadPersistedSegmentsIfNeeded()
        viewModel.updateLabelSegments([todayLabel])

        #expect(viewModel.labelSegments.contains {
            $0.id == spanningLabel.id
                && $0.label == spanningLabel.label
                && $0.startDate == spanningStart
                && $0.endDate == todayStart
        })
        #expect(!viewModel.labelSegments.contains {
            $0.id == spanningLabel.id && $0.startDate < todayStart && $0.endDate > todayStart
        })
        #expect(viewModel.labelSegments.contains {
            $0.label == todayLabel.label
                && $0.startDate == todayLabel.startDate
                && $0.endDate == todayLabel.endDate
        })
    }

    @Test("deleting recurring manual occurrence removes parent event")
    @MainActor
    func deletingRecurringManualOccurrenceRemovesParentEvent() async throws {
        ManualActivityEventStore.clear()
        defer { ManualActivityEventStore.clear() }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .hour, value: 9, to: todayStart) ?? todayStart.addingTimeInterval(9 * 60 * 60)
        let endDate = calendar.date(byAdding: .hour, value: 10, to: todayStart) ?? startDate.addingTimeInterval(60 * 60)
        let event = ManualActivityEvent(
            id: UUID(uuidString: "67676767-8989-1010-2323-454545454545")!,
            title: "Daily planning",
            startDate: startDate,
            endDate: endDate,
            label: .productive,
            recurrence: .daily
        )
        let dayInterval = DateInterval(start: todayStart, end: calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart.addingTimeInterval(86_400))
        let occurrence = try #require(event.segments(in: dayInterval).first)
        let viewModel = DashboardViewModel(
            activityTracker: SequenceActivityTracker(snapshots: []),
            insightEngine: InsightEngine(),
            activityRepository: InMemoryActivityRepository(segments: []),
            timelineLabelRepository: InMemoryTimelineLabelRepository()
        )
        viewModel.manualEvents = [event]
        ManualActivityEventStore.save([event])

        await viewModel.deleteSegment(occurrence)

        #expect(viewModel.manualEvents.isEmpty)
        #expect(ManualActivityEventStore.load().isEmpty)
    }
}

@Suite("AppEnvironment tracking lifecycle")
struct AppEnvironmentTrackingLifecycleTests {

    @Test("enabling tracking starts the shared tracker only once")
    @MainActor
    func enablingTrackingStartsSharedTrackerOnlyOnce() async throws {
        let tracker = SuspendedActivityTracker()
        let rootDirectory = temporaryTestDirectory(named: "environment-start")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let environment = AppEnvironment(
            activityTracker: tracker,
            activityRepository: InMemoryActivityRepository(),
            timelineLabelRepository: InMemoryTimelineLabelRepository(),
            calendarBoardStore: CalendarBoardStore(storeURL: rootDirectory.appendingPathComponent("board.calendarboard")),
            pomodoroViewModel: PomodoroViewModel(configuration: testPomodoroConfiguration())
        )

        await environment.reconcileTracking(isEnabled: true)
        try await waitUntil { tracker.startCount == 1 }

        await environment.reconcileTracking(isEnabled: true)
        try await Task.sleep(for: .milliseconds(25))

        #expect(tracker.startCount == 1)
        #expect(environment.dashboardViewModel.trackingStatus == ActivityTrackingStatus.starting)

        await environment.stopTracking()
        tracker.finish()
    }

    @Test("disabling tracking stops the tracker and marks dashboard paused")
    @MainActor
    func disablingTrackingStopsTrackerAndMarksDashboardPaused() async throws {
        let tracker = SuspendedActivityTracker()
        let rootDirectory = temporaryTestDirectory(named: "environment-stop")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let environment = AppEnvironment(
            activityTracker: tracker,
            activityRepository: InMemoryActivityRepository(),
            timelineLabelRepository: InMemoryTimelineLabelRepository(),
            calendarBoardStore: CalendarBoardStore(storeURL: rootDirectory.appendingPathComponent("board.calendarboard")),
            pomodoroViewModel: PomodoroViewModel(configuration: testPomodoroConfiguration())
        )

        await environment.reconcileTracking(isEnabled: true)
        try await waitUntil { tracker.startCount == 1 }

        await environment.reconcileTracking(isEnabled: false)

        #expect(tracker.stopCount == 1)
        #expect(environment.dashboardViewModel.trackingStatus == ActivityTrackingStatus.paused)
        #expect(environment.activityTracker.isCapturingLiveActivity == false)

        tracker.finish()
    }
}

@Suite("TimelineLabelRepository contracts")
struct TimelineLabelRepositoryContractTests {

    @Test("in-memory label replacement preserves boundary-adjacent labels")
    @MainActor
    func inMemoryLabelReplacementPreservesBoundaryAdjacentLabels() async throws {
        let repository = InMemoryTimelineLabelRepository()
        let previousDayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            label: .productive,
            startDate: userDate(23),
            endDate: userDate(24)
        )
        let todayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            label: .unproductive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )
        try await repository.replaceLabelSegments([previousDayLabel], in: DateInterval(start: userDate(23), end: userDate(24)))

        try await repository.replaceLabelSegments([todayLabel], in: DateInterval(start: userDate(24), end: userDate(25)))
        let labels = try await repository.allLabelSegments()

        #expect(labels.contains {
            $0.label == previousDayLabel.label
                && $0.startDate == previousDayLabel.startDate
                && $0.endDate == previousDayLabel.endDate
        })
        #expect(labels.contains {
            $0.label == todayLabel.label
                && $0.startDate == todayLabel.startDate
                && $0.endDate == todayLabel.endDate
        })
    }

    @Test("in-memory label replacement preserves existing label portions outside the interval")
    @MainActor
    func inMemoryLabelReplacementPreservesOutsidePortions() async throws {
        let repository = InMemoryTimelineLabelRepository()
        let originalLabel = TimelineLabelSegment(
            id: UUID(uuidString: "ABABABAB-ABAB-ABAB-ABAB-ABABABABABAB")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 12)
        )
        let replacementLabel = TimelineLabelSegment(
            label: .unproductive,
            startDate: userDate(24, hour: 10),
            endDate: userDate(24, hour: 11)
        )

        try await repository.replaceLabelSegments([originalLabel], in: DateInterval(start: userDate(24), end: userDate(25)))
        try await repository.replaceLabelSegments(
            [replacementLabel],
            in: DateInterval(start: userDate(24, hour: 10), end: userDate(24, hour: 11))
        )

        let labels = try await repository.allLabelSegments()

        #expect(labels.count == 3)
        #expect(labels.contains {
            $0.label == .productive
                && $0.startDate == userDate(24, hour: 9)
                && $0.endDate == userDate(24, hour: 10)
        })
        #expect(labels.contains {
            $0.label == .unproductive
                && $0.startDate == userDate(24, hour: 10)
                && $0.endDate == userDate(24, hour: 11)
        })
        #expect(labels.contains {
            $0.label == .productive
                && $0.startDate == userDate(24, hour: 11)
                && $0.endDate == userDate(24, hour: 12)
        })
    }

    @Test("normalizing a contained label split keeps unique segment IDs")
    func normalizedContainedSplitKeepsUniqueIDs() {
        let outerLabelID = UUID(uuidString: "ABCDABCD-ABCD-ABCD-ABCD-ABCDABCDABCD")!
        let outerLabel = TimelineLabelSegment(
            id: outerLabelID,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 12)
        )
        let innerLabel = TimelineLabelSegment(
            id: UUID(uuidString: "DCDCDCDC-DCDC-DCDC-DCDC-DCDCDCDCDCDC")!,
            label: .unproductive,
            startDate: userDate(24, hour: 10),
            endDate: userDate(24, hour: 11)
        )

        let labels = TimelineLabelSegment.normalized([outerLabel, innerLabel])
        let uniqueIDs = Set(labels.map(\.id))

        #expect(labels.count == 3)
        #expect(uniqueIDs.count == labels.count)
        #expect(labels.filter { $0.label == outerLabel.label }.count == 2)
        #expect(labels.contains { $0.id == outerLabelID && $0.startDate == userDate(24, hour: 9) && $0.endDate == userDate(24, hour: 10) })
    }

    @Test("file-backed label repository splits cross-midnight labels and reloads them")
    @MainActor
    func fileBackedLabelRepositorySplitsCrossMidnightLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let labelSegment = TimelineLabelSegment(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            label: .productive,
            startDate: userDate(24, hour: 23),
            endDate: userDate(25, hour: 1)
        )
        let replacementInterval = DateInterval(start: userDate(24, hour: 23), end: userDate(25, hour: 1))

        try await repository.replaceLabelSegments([labelSegment], in: replacementInterval)
        let restartedRepository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let firstDayLabels = try await restartedRepository.labelSegments(
            for: DateInterval(start: userDate(24), end: userDate(25))
        )
        let secondDayLabels = try await restartedRepository.labelSegments(
            for: DateInterval(start: userDate(25), end: userDate(26))
        )

        #expect(firstDayLabels.count == 1)
        #expect(firstDayLabels.first?.startDate == userDate(24, hour: 23))
        #expect(firstDayLabels.first?.endDate == userDate(25))
        #expect(secondDayLabels.count == 1)
        #expect(secondDayLabels.first?.startDate == userDate(25))
        #expect(secondDayLabels.first?.endDate == userDate(25, hour: 1))
    }

    @Test("file-backed label replacement removes previous-day labels that overlap the replacement interval")
    @MainActor
    func fileBackedLabelReplacementRemovesPreviousDayOverlap() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels-previous-day-overlap")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let overnightLabel = TimelineLabelSegment(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            label: .productive,
            startDate: userDate(24, hour: 23),
            endDate: userDate(25, hour: 1)
        )
        let replacementLabel = TimelineLabelSegment(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            label: .unproductive,
            startDate: userDate(25),
            endDate: userDate(25, hour: 1)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([overnightLabel]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-24", isDirectory: false)
                .appendingPathExtension("timelinelabels")
        )

        try await repository.replaceLabelSegments(
            [replacementLabel],
            in: DateInterval(start: userDate(25), end: userDate(26))
        )

        let restartedRepository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let labels = try await restartedRepository.labelSegments(
            for: DateInterval(start: userDate(25), end: userDate(25, hour: 2))
        )
        let previousDayLabels = try await restartedRepository.labelSegments(
            for: DateInterval(start: userDate(24), end: userDate(25))
        )

        #expect(labels.count == 1)
        #expect(labels.first?.label == replacementLabel.label)
        #expect(labels.first?.startDate == replacementLabel.startDate)
        #expect(labels.first?.endDate == replacementLabel.endDate)
        #expect(previousDayLabels.count == 1)
        #expect(previousDayLabels.first?.label == overnightLabel.label)
        #expect(previousDayLabels.first?.startDate == overnightLabel.startDate)
        #expect(previousDayLabels.first?.endDate == userDate(25))
    }

    @Test("file-backed label repository quarantines corrupt day files and keeps loading healthy days")
    @MainActor
    func fileBackedLabelRepositoryQuarantinesCorruptDayFiles() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels-corrupt-day")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let healthyLabel = TimelineLabelSegment(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            label: .productive,
            startDate: userDate(25, hour: 9),
            endDate: userDate(25, hour: 10)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([healthyLabel]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-25", isDirectory: false)
                .appendingPathExtension("timelinelabels")
        )
        let corruptDayFile = rootDirectory
            .appendingPathComponent("2026-08-24", isDirectory: false)
            .appendingPathExtension("timelinelabels")
        try Data("not a property list".utf8).write(to: corruptDayFile)
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let labels = try await repository.allLabelSegments()
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)

        #expect(labels == [healthyLabel])
        #expect(!FileManager.default.fileExists(atPath: corruptDayFile.path))
        #expect(remainingFiles.contains { $0.hasPrefix("2026-08-24.timelinelabels.corrupt-") })
    }

    @Test("file-backed label repository full-day query does not load exclusive end day")
    @MainActor
    func fileBackedLabelRepositoryFullDayQuerySkipsExclusiveEndDayFile() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels-exclusive-end-day")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let label = TimelineLabelSegment(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([label]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-24", isDirectory: false)
                .appendingPathExtension("timelinelabels")
        )
        let exclusiveEndDayFile = rootDirectory
            .appendingPathComponent("2026-08-25", isDirectory: false)
            .appendingPathExtension("timelinelabels")
        try Data("not a property list".utf8).write(to: exclusiveEndDayFile)
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let labels = try await repository.labelSegments(for: DateInterval(start: userDate(24), end: userDate(25)))
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: rootDirectory.path)

        #expect(labels == [label])
        #expect(FileManager.default.fileExists(atPath: exclusiveEndDayFile.path))
        #expect(!remainingFiles.contains { $0.hasPrefix("2026-08-25.timelinelabels.corrupt-") })
    }

    @Test("file-backed label all-read returns canonical cross-midnight labels")
    @MainActor
    func fileBackedLabelAllReadReturnsCanonicalCrossMidnightLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels-all-canonical")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)
        let label = TimelineLabelSegment(
            id: UUID(uuidString: "EFEFEFEF-EFEF-EFEF-EFEF-EFEFEFEFEFEF")!,
            label: .productive,
            startDate: userDate(24, hour: 23),
            endDate: userDate(25, hour: 1)
        )

        try await repository.replaceLabelSegments([label], in: DateInterval(start: label.startDate, end: label.endDate))
        let restartedRepository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let labels = try await restartedRepository.allLabelSegments()

        #expect(labels.count == 1)
        #expect(labels.first?.label == label.label)
        #expect(labels.first?.startDate == label.startDate)
        #expect(labels.first?.endDate == label.endDate)
    }

    @Test("file-backed label repository normalizes overlapping persisted labels")
    @MainActor
    func fileBackedLabelRepositoryNormalizesOverlappingPersistedLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "timeline-labels-normalized-load")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let olderLabel = TimelineLabelSegment(
            id: UUID(uuidString: "F0F0F0F0-F0F0-F0F0-F0F0-F0F0F0F0F0F0")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 11)
        )
        let newerLabel = TimelineLabelSegment(
            id: UUID(uuidString: "F1F1F1F1-F1F1-F1F1-F1F1-F1F1F1F1F1F1")!,
            label: .unproductive,
            startDate: userDate(24, hour: 10),
            endDate: userDate(24, hour: 12)
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode([olderLabel, newerLabel]).write(
            to: rootDirectory
                .appendingPathComponent("2026-08-24", isDirectory: false)
                .appendingPathExtension("timelinelabels")
        )
        let repository = FileBackedTimelineLabelRepository(rootDirectory: rootDirectory, calendar: userCalendar)

        let labels = try await repository.labelSegments(for: DateInterval(start: userDate(24), end: userDate(25)))

        #expect(labels.count == 2)
        #expect(labels.contains { $0.label == .productive && $0.startDate == userDate(24, hour: 9) && $0.endDate == userDate(24, hour: 10) })
        #expect(labels.contains { $0.label == .unproductive && $0.startDate == userDate(24, hour: 10) && $0.endDate == userDate(24, hour: 12) })
    }

    @Test("SQLite label repository persists both sides of a contained split")
    @MainActor
    func sqliteLabelRepositoryPersistsBothSidesOfContainedSplit() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-contained-split")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let outerLabel = TimelineLabelSegment(
            id: UUID(uuidString: "D0D0D0D0-D0D0-D0D0-D0D0-D0D0D0D0D0D0")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 12)
        )
        let innerLabel = TimelineLabelSegment(
            id: UUID(uuidString: "D1D1D1D1-D1D1-D1D1-D1D1-D1D1D1D1D1D1")!,
            label: .unproductive,
            startDate: userDate(24, hour: 10),
            endDate: userDate(24, hour: 11)
        )

        try await repository.replaceLabelSegments([outerLabel, innerLabel], in: DateInterval(start: userDate(24), end: userDate(25)))
        let labels = try await repository.allLabelSegments()

        #expect(labels.count == 3)
        #expect(Set(labels.map(\.id)).count == labels.count)
        #expect(labels.contains { $0.label == .productive && $0.startDate == userDate(24, hour: 9) && $0.endDate == userDate(24, hour: 10) })
        #expect(labels.contains { $0.label == .unproductive && $0.startDate == userDate(24, hour: 10) && $0.endDate == userDate(24, hour: 11) })
        #expect(labels.contains { $0.label == .productive && $0.startDate == userDate(24, hour: 11) && $0.endDate == userDate(24, hour: 12) })
    }
}

@Suite("SQLiteTimelineLabelRepository contracts")
struct SQLiteTimelineLabelRepositoryContractTests {

    @Test("SQLite label replacement preserves existing label portions outside the interval")
    @MainActor
    func sqliteLabelReplacementPreservesOutsidePortions() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-outside")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let originalLabel = TimelineLabelSegment(
            id: UUID(uuidString: "B3B3B3B3-B3B3-B3B3-B3B3-B3B3B3B3B3B3")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 12)
        )
        let replacementLabel = TimelineLabelSegment(
            id: UUID(uuidString: "B4B4B4B4-B4B4-B4B4-B4B4-B4B4B4B4B4B4")!,
            label: .unproductive,
            startDate: userDate(24, hour: 10),
            endDate: userDate(24, hour: 11)
        )

        try await repository.replaceLabelSegments([originalLabel], in: DateInterval(start: userDate(24), end: userDate(25)))
        try await repository.replaceLabelSegments(
            [replacementLabel],
            in: DateInterval(start: userDate(24, hour: 10), end: userDate(24, hour: 11))
        )

        let labels = try await repository.allLabelSegments()

        #expect(labels.count == 3)
        #expect(labels.contains { $0.label == .productive && $0.startDate == userDate(24, hour: 9) && $0.endDate == userDate(24, hour: 10) })
        #expect(labels.contains { $0.label == .unproductive && $0.startDate == userDate(24, hour: 10) && $0.endDate == userDate(24, hour: 11) })
        #expect(labels.contains { $0.label == .productive && $0.startDate == userDate(24, hour: 11) && $0.endDate == userDate(24, hour: 12) })
    }

    @Test("SQLite label repository reloads cross-midnight labels canonically")
    @MainActor
    func sqliteLabelRepositoryReloadsCrossMidnightLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-cross-midnight")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let label = TimelineLabelSegment(
            id: UUID(uuidString: "B5B5B5B5-B5B5-B5B5-B5B5-B5B5B5B5B5B5")!,
            label: .productive,
            startDate: userDate(24, hour: 23),
            endDate: userDate(25, hour: 1)
        )
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        try await repository.replaceLabelSegments([label], in: DateInterval(start: label.startDate, end: label.endDate))
        let restartedRepository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)

        #expect(try await restartedRepository.allLabelSegments() == [label])
        #expect(try await restartedRepository.labelSegments(for: DateInterval(start: userDate(25), end: userDate(26))) == [label])
    }

    @Test("SQLite label repository deletes all label segments")
    @MainActor
    func sqliteLabelRepositoryDeletesAllLabelSegments() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-delete-all")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let label = TimelineLabelSegment(
            id: UUID(uuidString: "C4C4C4C4-C4C4-C4C4-C4C4-C4C4C4C4C4C4")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )

        try await repository.replaceLabelSegments([label], in: DateInterval(start: userDate(24), end: userDate(25)))
        try await repository.deleteAllLabelSegments()
        let remaining = try await repository.allLabelSegments()

        #expect(remaining.isEmpty)
    }

    @Test("SQLite label replacement preserves boundary-adjacent labels")
    @MainActor
    func sqliteLabelReplacementPreservesBoundaryAdjacentLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-boundary-adjacent")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let previousDayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "C5C5C5C5-C5C5-C5C5-C5C5-C5C5C5C5C5C5")!,
            label: .productive,
            startDate: userDate(23),
            endDate: userDate(24)
        )
        let todayLabel = TimelineLabelSegment(
            id: UUID(uuidString: "C6C6C6C6-C6C6-C6C6-C6C6-C6C6C6C6C6C6")!,
            label: .unproductive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )

        try await repository.replaceLabelSegments([previousDayLabel], in: DateInterval(start: userDate(23), end: userDate(24)))
        try await repository.replaceLabelSegments([todayLabel], in: DateInterval(start: userDate(24), end: userDate(25)))
        let labels = try await repository.allLabelSegments()

        #expect(labels.contains {
            $0.label == previousDayLabel.label
                && $0.startDate == previousDayLabel.startDate
                && $0.endDate == previousDayLabel.endDate
        })
        #expect(labels.contains {
            $0.label == todayLabel.label
                && $0.startDate == todayLabel.startDate
                && $0.endDate == todayLabel.endDate
        })
    }

    @Test("SQLite label replacement does not overwrite non-overlapping rows with reused IDs")
    @MainActor
    func sqliteLabelReplacementDoesNotOverwriteNonOverlappingReusedID() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-reused-id")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let repository = SQLiteBackedTimelineLabelRepository(databaseURL: databaseURL, legacyRootDirectory: nil, calendar: userCalendar, migratesLegacyStore: false)
        let labelID = UUID(uuidString: "C7C7C7C7-C7C7-C7C7-C7C7-C7C7C7C7C7C7")!
        let firstLabel = TimelineLabelSegment(
            id: labelID,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )
        let reusedIDLabel = TimelineLabelSegment(
            id: labelID,
            label: .unproductive,
            startDate: userDate(24, hour: 11),
            endDate: userDate(24, hour: 12)
        )

        try await repository.replaceLabelSegments([firstLabel], in: DateInterval(start: firstLabel.startDate, end: firstLabel.endDate))
        try await repository.replaceLabelSegments([reusedIDLabel], in: DateInterval(start: reusedIDLabel.startDate, end: reusedIDLabel.endDate))
        let labels = try await repository.allLabelSegments()

        #expect(labels.count == 2)
        #expect(Set(labels.map(\.id)).count == labels.count)
        #expect(labels.contains { $0.label == firstLabel.label && $0.startDate == firstLabel.startDate && $0.endDate == firstLabel.endDate })
        #expect(labels.contains { $0.label == reusedIDLabel.label && $0.startDate == reusedIDLabel.startDate && $0.endDate == reusedIDLabel.endDate })
    }

    @Test("SQLite label repository migrates legacy file-backed labels once")
    @MainActor
    func sqliteLabelRepositoryMigratesLegacyLabels() async throws {
        let rootDirectory = temporaryTestDirectory(named: "sqlite-labels-migration")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let legacyRootDirectory = rootDirectory.appendingPathComponent("TimelineLabels", isDirectory: true)
        let databaseURL = rootDirectory.appendingPathComponent("activity.sqlite")
        let legacyLabel = TimelineLabelSegment(
            id: UUID(uuidString: "B6B6B6B6-B6B6-B6B6-B6B6-B6B6B6B6B6B6")!,
            label: .productive,
            startDate: userDate(24, hour: 9),
            endDate: userDate(24, hour: 10)
        )
        let legacyRepository = FileBackedTimelineLabelRepository(rootDirectory: legacyRootDirectory, calendar: userCalendar)
        try await legacyRepository.replaceLabelSegments([legacyLabel], in: DateInterval(start: userDate(24), end: userDate(25)))

        let repository = SQLiteBackedTimelineLabelRepository(
            databaseURL: databaseURL,
            legacyRootDirectory: legacyRootDirectory,
            calendar: userCalendar
        )

        #expect(try await repository.allLabelSegments() == [legacyLabel])
    }
}

@Suite("CalendarBoardStore persistence")
struct CalendarBoardStorePersistenceTests {

    @Test("calendar board store saves and reloads goals and normalized pins")
    @MainActor
    func calendarBoardStoreSavesAndReloadsGoalsAndPins() throws {
        let rootDirectory = temporaryTestDirectory(named: "calendar-board")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storeURL = rootDirectory.appendingPathComponent("board.calendarboard", isDirectory: false)
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
            name: "Workout",
            markerID: "workout",
            targetCount: 3,
            period: .weekly
        )
        let store = CalendarBoardStore(storeURL: storeURL)

        store.replaceGoals([goal])
        store.replacePins([
            "2026-08-24": ["🏃", "workout", "custom.deep-work"],
            "2026-08-25": []
        ])

        let reloadedStore = CalendarBoardStore(storeURL: storeURL)

        #expect(reloadedStore.goals == [goal])
        #expect(reloadedStore.pins == ["2026-08-24": ["workout", "custom.deep-work"]])
    }

    @Test("calendar board store clear persists empty board")
    @MainActor
    func calendarBoardStoreClearPersistsEmptyBoard() throws {
        let rootDirectory = temporaryTestDirectory(named: "calendar-board-clear")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storeURL = rootDirectory.appendingPathComponent("board.calendarboard", isDirectory: false)
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
            name: "Study",
            markerID: "study",
            targetCount: 5,
            period: .monthly
        )
        let store = CalendarBoardStore(storeURL: storeURL)

        store.replaceGoals([goal])
        store.replacePins(["2026-08-24": ["study"]])
        store.clear()

        let reloadedStore = CalendarBoardStore(storeURL: storeURL)

        #expect(reloadedStore.goals.isEmpty)
        #expect(reloadedStore.pins.isEmpty)
    }

    @Test("calendar board store heals corrupt persisted file")
    @MainActor
    func calendarBoardStoreHealsCorruptPersistedFile() throws {
        let rootDirectory = temporaryTestDirectory(named: "calendar-board-corrupt")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let storeURL = rootDirectory.appendingPathComponent("board.calendarboard", isDirectory: false)
        try Data("not a property list".utf8).write(to: storeURL)

        let store = CalendarBoardStore(storeURL: storeURL)
        let reloadedStore = CalendarBoardStore(storeURL: storeURL)
        let healedData = try Data(contentsOf: storeURL)

        #expect(store.goals.isEmpty)
        #expect(store.pins.isEmpty)
        #expect(reloadedStore.goals.isEmpty)
        #expect(reloadedStore.pins.isEmpty)
        #expect(healedData != Data("not a property list".utf8))
    }

    @Test("goal summary uses reference date for marked-day badges")
    @MainActor
    func goalSummaryUsesReferenceDateForMarkedDayBadges() {
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "12121212-3434-5656-7878-909090909090")!,
            name: "Study",
            markerID: "study",
            targetCount: 1,
            period: .weekly
        )
        let summary = GoalBoardSummary(
            goals: [goal],
            pins: ["2026-08-24": ["study"]],
            referenceDate: userDate(24)
        )

        #expect(summary.items.first?.isPinnedToday == true)
    }

    @Test("monthly weekly-goal target does not include exclusive end boundary")
    @MainActor
    func monthlyWeeklyGoalTargetExcludesExclusiveEndBoundary() {
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "23232323-4545-6767-8989-101010101010")!,
            name: "Workout",
            markerID: "workout",
            targetCount: 2,
            period: .weekly
        )
        let summary = GoalBoardSummary(
            goals: [goal],
            pins: [:],
            scope: .month,
            referenceDate: userDate(15, month: 7, year: 2026),
            calendar: userCalendar
        )

        #expect(summary.items.first?.progress.targetCount == 10)
    }

    @Test("calendar board store normalizes legacy marker IDs on goals and pins")
    @MainActor
    func calendarBoardStoreNormalizesLegacyGoalMarkerIDs() throws {
        let rootDirectory = temporaryTestDirectory(named: "calendar-board-legacy-goals")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storeURL = rootDirectory.appendingPathComponent("board.calendarboard", isDirectory: false)
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "34343434-5656-7878-9090-121212121212")!,
            name: "Workout",
            markerID: "🏃",
            targetCount: 1,
            period: .weekly
        )
        let store = CalendarBoardStore(storeURL: storeURL)

        store.replaceGoals([goal])
        store.replacePins(["2026-08-24": ["🏃"]])
        let reloadedStore = CalendarBoardStore(storeURL: storeURL)
        let summary = GoalBoardSummary(
            goals: reloadedStore.goals,
            pins: reloadedStore.pins,
            scope: .week,
            referenceDate: userDate(24),
            calendar: userCalendar
        )

        #expect(reloadedStore.goals.first?.markerID == "workout")
        #expect(reloadedStore.pins == ["2026-08-24": ["workout"]])
        #expect(summary.items.first?.marker.id == "workout")
        #expect(summary.items.first?.progress.completedCount == 1)
    }

    @Test("calendar board store clamps invalid persisted goal targets")
    @MainActor
    func calendarBoardStoreClampsInvalidGoalTargets() throws {
        let rootDirectory = temporaryTestDirectory(named: "calendar-board-invalid-targets")
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let storeURL = rootDirectory.appendingPathComponent("board.calendarboard", isDirectory: false)
        let weeklyGoal = CalendarActivityGoal(
            id: UUID(uuidString: "56565656-7878-9090-1010-343434343434")!,
            name: "Workout",
            markerID: "workout",
            targetCount: 0,
            period: .weekly
        )
        let monthlyGoal = CalendarActivityGoal(
            id: UUID(uuidString: "67676767-8989-1010-2323-454545454545")!,
            name: "Study",
            markerID: "study",
            targetCount: 99,
            period: .monthly
        )
        let store = CalendarBoardStore(storeURL: storeURL)

        store.replaceGoals([weeklyGoal, monthlyGoal])
        let reloadedStore = CalendarBoardStore(storeURL: storeURL)

        #expect(reloadedStore.goals.map(\.targetCount) == [1, 31])
    }

    @Test("future selected goal periods are not clamped before their start date")
    @MainActor
    func futureSelectedGoalPeriodsRemainValid() {
        let goal = CalendarActivityGoal(
            id: UUID(uuidString: "45454545-6767-8989-1010-232323232323")!,
            name: "Study",
            markerID: "study",
            targetCount: 4,
            period: .monthly
        )
        let summary = GoalBoardSummary(
            goals: [goal],
            pins: ["2099-09-01": ["study"]],
            scope: .month,
            referenceDate: userDate(15, month: 9, year: 2099),
            calendar: userCalendar
        )

        #expect(summary.items.first?.progress.completedCount == 1)
        #expect(summary.items.first?.progress.targetCount == 4)
    }
}

@MainActor
private final class SequenceActivityTracker: ActivityTracking {
    private let snapshots: [[ActivitySegment]]

    init(snapshots: [[ActivitySegment]]) {
        self.snapshots = snapshots
    }

    var activitySegments: AsyncStream<[ActivitySegment]> {
        AsyncStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }

    var currentSegments: [ActivitySegment] {
        snapshots.last ?? []
    }

    var isCapturingLiveActivity: Bool {
        currentSegments.isEmpty == false
    }

    func start() async {}
    func stop() async {}
}

@MainActor
private final class SuspendedActivityTracker: ActivityTracking {
    private var continuation: AsyncStream<[ActivitySegment]>.Continuation?
    private var isStarted = false
    private(set) var startCount = 0
    private(set) var stopCount = 0

    var activitySegments: AsyncStream<[ActivitySegment]> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    var currentSegments: [ActivitySegment] {
        []
    }

    var isCapturingLiveActivity: Bool {
        isStarted
    }

    func start() async {
        startCount += 1
        isStarted = true
    }

    func stop() async {
        stopCount += 1
        isStarted = false
        continuation?.finish()
    }

    func finish() {
        continuation?.finish()
    }
}

@MainActor
private final class RecordingActivityRepository: ActivityRepository, @unchecked Sendable {
    private var savedBatches: [[ActivitySegment]] = []
    private var segments: [ActivitySegment] = []

    func allSegments() async throws -> [ActivitySegment] {
        segments
    }

    func savedBatchesSnapshot() -> [[ActivitySegment]] {
        savedBatches
    }

    func segments(for interval: DateInterval) async throws -> [ActivitySegment] {
        segments.filter { segment in
            guard let segmentInterval = segment.safeInterval else { return false }
            return interval.intersects(segmentInterval)
        }
    }

    func save(_ segments: [ActivitySegment]) async throws {
        savedBatches.append(segments)
        var segmentsByID = Dictionary(uniqueKeysWithValues: self.segments.map { ($0.id, $0) })
        for segment in segments {
            segmentsByID[segment.id] = segment
        }
        self.segments = Array(segmentsByID.values)
    }

    func deleteSegments(identifiedBy ids: Set<UUID>) async throws {
        segments.removeAll { ids.contains($0.id) }
    }

    func deleteAllSegments() async throws {
        segments.removeAll()
    }

    func flush() async throws {}
}

private final class CountingInsightEngine: InsightGenerating {
    private let engine = InsightEngine()
    private(set) var dailyOverviewCallCount = 0

    func dailyOverview(from segments: [ActivitySegment], on date: Date) -> DailyActivityOverview {
        dailyOverviewCallCount += 1
        return engine.dailyOverview(from: segments, on: date)
    }

    func summaries(from overview: DailyActivityOverview) -> [InsightSummary] {
        engine.summaries(from: overview)
    }
}

private func temporaryTestDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("ProductivityTests-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func testPomodoroConfiguration() -> PomodoroConfiguration {
    PomodoroConfiguration(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 15,
        sessionsBeforeLongBreak: 4
    )
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
    while await !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out waiting for async condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
