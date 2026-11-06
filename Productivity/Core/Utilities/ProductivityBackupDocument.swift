import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct ProductivityBackupSnapshot: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var preferences: ProductivityPreferenceBackup
    var activitySegments: [ActivitySegment]
    var timelineLabelSegments: [TimelineLabelSegment]
    var manualEvents: [ManualActivityEvent]
    var appLabelRules: [AppLabelRule]
    var manualTrackingRules: [AppLabelRule]
    var customActivityLabels: [ActivityLabelDefinition]
    var calendarGoals: [CalendarActivityGoalBackup]
    var calendarPins: [String: [String]]
    var pomodoroConfiguration: PomodoroConfigurationBackup
    var pomodoroSessionHistory: [PomodoroSessionRecordBackup]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        exportedAt: Date = Date(),
        preferences: ProductivityPreferenceBackup,
        activitySegments: [ActivitySegment],
        timelineLabelSegments: [TimelineLabelSegment],
        manualEvents: [ManualActivityEvent],
        appLabelRules: [AppLabelRule],
        manualTrackingRules: [AppLabelRule],
        customActivityLabels: [ActivityLabelDefinition] = ActivityLabelCatalog.customDefinitions(),
        calendarGoals: [CalendarActivityGoalBackup],
        calendarPins: [String: [String]],
        pomodoroConfiguration: PomodoroConfigurationBackup,
        pomodoroSessionHistory: [PomodoroSessionRecordBackup]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.preferences = preferences
        self.activitySegments = activitySegments
        self.timelineLabelSegments = timelineLabelSegments
        self.manualEvents = manualEvents
        self.appLabelRules = appLabelRules
        self.manualTrackingRules = manualTrackingRules
        self.customActivityLabels = customActivityLabels
        self.calendarGoals = calendarGoals
        self.calendarPins = calendarPins
        self.pomodoroConfiguration = pomodoroConfiguration
        self.pomodoroSessionHistory = pomodoroSessionHistory
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportedAt
        case preferences
        case activitySegments
        case timelineLabelSegments
        case manualEvents
        case appLabelRules
        case manualTrackingRules
        case customActivityLabels
        case calendarGoals
        case calendarPins
        case pomodoroConfiguration
        case pomodoroSessionHistory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        preferences = try container.decode(ProductivityPreferenceBackup.self, forKey: .preferences)
        activitySegments = try container.decode([ActivitySegment].self, forKey: .activitySegments)
        timelineLabelSegments = try container.decode([TimelineLabelSegment].self, forKey: .timelineLabelSegments)
        manualEvents = try container.decode([ManualActivityEvent].self, forKey: .manualEvents)
        appLabelRules = try container.decode([AppLabelRule].self, forKey: .appLabelRules)
        manualTrackingRules = try container.decode([AppLabelRule].self, forKey: .manualTrackingRules)
        customActivityLabels = try container.decodeIfPresent([ActivityLabelDefinition].self, forKey: .customActivityLabels) ?? []
        calendarGoals = try container.decode([CalendarActivityGoalBackup].self, forKey: .calendarGoals)
        calendarPins = try container.decode([String: [String]].self, forKey: .calendarPins)
        pomodoroConfiguration = try container.decode(PomodoroConfigurationBackup.self, forKey: .pomodoroConfiguration)
        pomodoroSessionHistory = try container.decode([PomodoroSessionRecordBackup].self, forKey: .pomodoroSessionHistory)
    }

    static func decode(from url: URL) throws -> ProductivityBackupSnapshot {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(ProductivityBackupSnapshot.self, from: data)
    }
}

struct CalendarActivityGoalBackup: Codable, Hashable {
    var id: UUID
    var name: String
    var markerID: String
    var symbol: String?
    var targetCount: Int
    var period: String
}

struct PomodoroConfigurationBackup: Codable, Hashable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int

    static var storedDefaults: PomodoroConfigurationBackup {
        let configuration = PomodoroConfiguration.storedDefaults()
        return PomodoroConfigurationBackup(
            focusMinutes: configuration.focusMinutes,
            shortBreakMinutes: configuration.shortBreakMinutes,
            longBreakMinutes: configuration.longBreakMinutes,
            sessionsBeforeLongBreak: configuration.sessionsBeforeLongBreak
        )
    }
}

struct PomodoroSessionRecordBackup: Codable, Hashable {
    var id: UUID
    var completedAt: Date
    var focusMinutes: Int
}

struct ProductivityPreferenceBackup: Codable {
    var appearance: String
    var textSize: String
    var theme: String
    var displayName: String
    var isTrackingEnabled: Bool
    var appTrackingMode: String
    var snapshotIntervalSeconds: TimeInterval
    var idleTimeoutSeconds: TimeInterval
    var visibleCompanionWindowSeconds: TimeInterval
    var timelineHorizonSeconds: TimeInterval
    var isTimelineEventContextOverlayEnabled: Bool
    var isSleepHiddenInDayProgress: Bool
    var isPomodoroSoundEnabled: Bool
    var pomodoroFocusStartSound: String
    var pomodoroShortBreakStartSound: String
    var pomodoroLongBreakStartSound: String
    var pomodoroCompletionSound: String
    var isDailyFocusHeaderEnabled: Bool
    var customMotivationQuote: String
    var productivityThresholdPercent: Int
    private static let defaultProductivityThresholdPercent = 70
    private static let productivityThresholdRange = 10...95

    enum CodingKeys: String, CodingKey {
        case appearance
        case textSize
        case theme
        case displayName
        case isTrackingEnabled
        case appTrackingMode
        case snapshotIntervalSeconds
        case idleTimeoutSeconds
        case visibleCompanionWindowSeconds
        case timelineHorizonSeconds
        case isTimelineEventContextOverlayEnabled
        case isSleepHiddenInDayProgress
        case isPomodoroSoundEnabled
        case pomodoroFocusStartSound
        case pomodoroShortBreakStartSound
        case pomodoroLongBreakStartSound
        case pomodoroCompletionSound
        case isDailyFocusHeaderEnabled
        case customMotivationQuote
        case productivityThresholdPercent
    }

    init(
        appearance: String,
        textSize: String,
        theme: String,
        displayName: String,
        isTrackingEnabled: Bool,
        appTrackingMode: String,
        snapshotIntervalSeconds: TimeInterval,
        idleTimeoutSeconds: TimeInterval,
        visibleCompanionWindowSeconds: TimeInterval,
        timelineHorizonSeconds: TimeInterval,
        isTimelineEventContextOverlayEnabled: Bool,
        isSleepHiddenInDayProgress: Bool,
        isPomodoroSoundEnabled: Bool,
        pomodoroFocusStartSound: String,
        pomodoroShortBreakStartSound: String,
        pomodoroLongBreakStartSound: String,
        pomodoroCompletionSound: String,
        isDailyFocusHeaderEnabled: Bool,
        customMotivationQuote: String,
        productivityThresholdPercent: Int
    ) {
        self.appearance = appearance
        self.textSize = textSize
        self.theme = theme
        self.displayName = displayName
        self.isTrackingEnabled = isTrackingEnabled
        self.appTrackingMode = appTrackingMode
        self.snapshotIntervalSeconds = snapshotIntervalSeconds
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.visibleCompanionWindowSeconds = visibleCompanionWindowSeconds
        self.timelineHorizonSeconds = timelineHorizonSeconds
        self.isTimelineEventContextOverlayEnabled = isTimelineEventContextOverlayEnabled
        self.isSleepHiddenInDayProgress = isSleepHiddenInDayProgress
        self.isPomodoroSoundEnabled = isPomodoroSoundEnabled
        self.pomodoroFocusStartSound = pomodoroFocusStartSound
        self.pomodoroShortBreakStartSound = pomodoroShortBreakStartSound
        self.pomodoroLongBreakStartSound = pomodoroLongBreakStartSound
        self.pomodoroCompletionSound = pomodoroCompletionSound
        self.isDailyFocusHeaderEnabled = isDailyFocusHeaderEnabled
        self.customMotivationQuote = customMotivationQuote
        self.productivityThresholdPercent = Self.clampedProductivityThreshold(productivityThresholdPercent)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decode(String.self, forKey: .appearance)
        textSize = try container.decodeIfPresent(String.self, forKey: .textSize) ?? AppTextSize.standard.rawValue
        theme = try container.decode(String.self, forKey: .theme)
        displayName = try container.decode(String.self, forKey: .displayName)
        isTrackingEnabled = try container.decode(Bool.self, forKey: .isTrackingEnabled)
        appTrackingMode = try container.decode(String.self, forKey: .appTrackingMode)
        snapshotIntervalSeconds = try container.decode(TimeInterval.self, forKey: .snapshotIntervalSeconds)
        idleTimeoutSeconds = try container.decode(TimeInterval.self, forKey: .idleTimeoutSeconds)
        visibleCompanionWindowSeconds = try container.decode(TimeInterval.self, forKey: .visibleCompanionWindowSeconds)
        timelineHorizonSeconds = try container.decode(TimeInterval.self, forKey: .timelineHorizonSeconds)
        isTimelineEventContextOverlayEnabled = try container.decode(Bool.self, forKey: .isTimelineEventContextOverlayEnabled)
        isSleepHiddenInDayProgress = try container.decode(Bool.self, forKey: .isSleepHiddenInDayProgress)
        isPomodoroSoundEnabled = try container.decode(Bool.self, forKey: .isPomodoroSoundEnabled)
        pomodoroFocusStartSound = try container.decodeIfPresent(String.self, forKey: .pomodoroFocusStartSound) ?? PomodoroSoundEvent.focusStart.defaultSound.rawValue
        pomodoroShortBreakStartSound = try container.decodeIfPresent(String.self, forKey: .pomodoroShortBreakStartSound) ?? PomodoroSoundEvent.shortBreakStart.defaultSound.rawValue
        pomodoroLongBreakStartSound = try container.decodeIfPresent(String.self, forKey: .pomodoroLongBreakStartSound) ?? PomodoroSoundEvent.longBreakStart.defaultSound.rawValue
        pomodoroCompletionSound = try container.decodeIfPresent(String.self, forKey: .pomodoroCompletionSound) ?? PomodoroSoundEvent.completion.defaultSound.rawValue
        isDailyFocusHeaderEnabled = try container.decode(Bool.self, forKey: .isDailyFocusHeaderEnabled)
        customMotivationQuote = try container.decode(String.self, forKey: .customMotivationQuote)
        productivityThresholdPercent = Self.clampedProductivityThreshold(
            try container.decodeIfPresent(Int.self, forKey: .productivityThresholdPercent) ?? Self.defaultProductivityThresholdPercent
        )
    }

    static func current(defaults: UserDefaults = .standard) -> ProductivityPreferenceBackup {
        ProductivityPreferenceBackup(
            appearance: defaults.string(forKey: AppPreferenceKeys.appearance) ?? AppAppearance.system.rawValue,
            textSize: defaults.string(forKey: AppTextSize.storageKey) ?? AppTextSize.standard.rawValue,
            theme: defaults.string(forKey: ProductivityTheme.storageKey) ?? AppTheme.amethyst.rawValue,
            displayName: defaults.string(forKey: AccountPreferenceKeys.displayName) ?? AccountPreferenceKeys.defaultDisplayName,
            isTrackingEnabled: bool(forKey: AppPreferenceKeys.isTrackingEnabled, defaultValue: true, defaults: defaults),
            appTrackingMode: defaults.string(forKey: AppLabelRuleStore.trackingModeKey) ?? AppTrackingMode.all.rawValue,
            snapshotIntervalSeconds: TrackingPreferences.snapshotIntervalSeconds(),
            idleTimeoutSeconds: TrackingPreferences.idleTimeoutSeconds(),
            visibleCompanionWindowSeconds: TrackingPreferences.visibleCompanionWindowSeconds(),
            timelineHorizonSeconds: TrackingPreferences.timelineHorizonSeconds(),
            isTimelineEventContextOverlayEnabled: bool(forKey: TrackingPreferenceKeys.isTimelineEventContextOverlayEnabled, defaultValue: true, defaults: defaults),
            isSleepHiddenInDayProgress: bool(forKey: TrackingPreferenceKeys.isSleepHiddenInDayProgress, defaultValue: true, defaults: defaults),
            isPomodoroSoundEnabled: bool(forKey: NotificationPreferenceKeys.isPomodoroSoundEnabled, defaultValue: true, defaults: defaults),
            pomodoroFocusStartSound: defaults.string(forKey: NotificationPreferenceKeys.pomodoroFocusStartSound) ?? PomodoroSoundEvent.focusStart.defaultSound.rawValue,
            pomodoroShortBreakStartSound: defaults.string(forKey: NotificationPreferenceKeys.pomodoroShortBreakStartSound) ?? PomodoroSoundEvent.shortBreakStart.defaultSound.rawValue,
            pomodoroLongBreakStartSound: defaults.string(forKey: NotificationPreferenceKeys.pomodoroLongBreakStartSound) ?? PomodoroSoundEvent.longBreakStart.defaultSound.rawValue,
            pomodoroCompletionSound: defaults.string(forKey: NotificationPreferenceKeys.pomodoroCompletionSound) ?? PomodoroSoundEvent.completion.defaultSound.rawValue,
            isDailyFocusHeaderEnabled: bool(forKey: AppPreferenceKeys.isDailyFocusHeaderEnabled, defaultValue: true, defaults: defaults),
            customMotivationQuote: defaults.string(forKey: AppPreferenceKeys.customMotivationQuote) ?? "",
            productivityThresholdPercent: clampedProductivityThreshold(
                defaults.object(forKey: AppPreferenceKeys.productivityThresholdPercent) as? Int ?? defaultProductivityThresholdPercent
            )
        )
    }

    func apply(defaults: UserDefaults = .standard) {
        defaults.set(appearance, forKey: AppPreferenceKeys.appearance)
        defaults.set(textSize, forKey: AppTextSize.storageKey)
        defaults.set(theme, forKey: ProductivityTheme.storageKey)
        defaults.set(displayName, forKey: AccountPreferenceKeys.displayName)
        defaults.set(isTrackingEnabled, forKey: AppPreferenceKeys.isTrackingEnabled)
        defaults.set(appTrackingMode, forKey: AppLabelRuleStore.trackingModeKey)
        defaults.set(snapshotIntervalSeconds, forKey: TrackingPreferenceKeys.snapshotIntervalSeconds)
        defaults.set(idleTimeoutSeconds, forKey: TrackingPreferenceKeys.idleTimeoutSeconds)
        defaults.set(visibleCompanionWindowSeconds, forKey: TrackingPreferenceKeys.visibleCompanionWindowSeconds)
        defaults.set(timelineHorizonSeconds, forKey: TrackingPreferenceKeys.timelineHorizonSeconds)
        defaults.set(isTimelineEventContextOverlayEnabled, forKey: TrackingPreferenceKeys.isTimelineEventContextOverlayEnabled)
        defaults.set(isSleepHiddenInDayProgress, forKey: TrackingPreferenceKeys.isSleepHiddenInDayProgress)
        defaults.set(isPomodoroSoundEnabled, forKey: NotificationPreferenceKeys.isPomodoroSoundEnabled)
        defaults.set(pomodoroFocusStartSound, forKey: NotificationPreferenceKeys.pomodoroFocusStartSound)
        defaults.set(pomodoroShortBreakStartSound, forKey: NotificationPreferenceKeys.pomodoroShortBreakStartSound)
        defaults.set(pomodoroLongBreakStartSound, forKey: NotificationPreferenceKeys.pomodoroLongBreakStartSound)
        defaults.set(pomodoroCompletionSound, forKey: NotificationPreferenceKeys.pomodoroCompletionSound)
        defaults.set(isDailyFocusHeaderEnabled, forKey: AppPreferenceKeys.isDailyFocusHeaderEnabled)
        defaults.set(customMotivationQuote, forKey: AppPreferenceKeys.customMotivationQuote)
        defaults.set(Self.clampedProductivityThreshold(productivityThresholdPercent), forKey: AppPreferenceKeys.productivityThresholdPercent)
    }

    private static func bool(forKey key: String, defaultValue: Bool, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    private static func clampedProductivityThreshold(_ value: Int) -> Int {
        min(max(value, productivityThresholdRange.lowerBound), productivityThresholdRange.upperBound)
    }
}

struct ProductivityBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    static var empty: ProductivityBackupDocument {
        ProductivityBackupDocument(data: Data())
    }

    @MainActor
    init(snapshot: ProductivityBackupSnapshot) throws {
        self.data = try Self.encodedData(for: snapshot)
    }

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }

    @MainActor
    private static func encodedData(for snapshot: ProductivityBackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }
}

extension Array where Element == TimelineLabelSegment {
    var restoreInterval: DateInterval? {
        guard let firstStart = map(\.startDate).min(), let lastEnd = map(\.endDate).max(), lastEnd > firstStart else {
            return nil
        }
        return DateInterval(start: firstStart, end: lastEnd)
    }
}
