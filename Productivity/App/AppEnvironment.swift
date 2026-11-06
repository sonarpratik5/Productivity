import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let activityTracker: any ActivityTracking
    let insightEngine: any InsightGenerating
    let activityRepository: any ActivityRepository
    let timelineLabelRepository: any TimelineLabelRepository
    let calendarBoardStore: CalendarBoardStore
    let appSettings: AppSettings
    let pomodoroViewModel: PomodoroViewModel
    let dashboardViewModel: DashboardViewModel
    var lifecycleRefreshID = UUID()
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let lifecycleRecorder: ActivityLifecycleRecorder
    @ObservationIgnored private var trackingTask: Task<Void, Never>?
    @ObservationIgnored private var trackingTaskID: UUID?
    @ObservationIgnored private var isReconcilingTracking = false
    @ObservationIgnored private var desiredTrackingEnabled = false
    @ObservationIgnored private var widgetSyncTask: Task<Void, Never>?
    @ObservationIgnored private var widgetBoardChangeObserver: UnsafeRawPointer?

    init(
        activityTracker: (any ActivityTracking)? = nil,
        insightEngine: (any InsightGenerating)? = nil,
        activityRepository: (any ActivityRepository)? = nil,
        timelineLabelRepository: (any TimelineLabelRepository)? = nil,
        calendarBoardStore: CalendarBoardStore? = nil,
        appSettings: AppSettings? = nil,
        pomodoroViewModel: PomodoroViewModel? = nil
    ) {
        self.activityTracker = activityTracker ?? MacOSActivityTracker()
        self.insightEngine = insightEngine ?? InsightEngine()
        self.activityRepository = activityRepository ?? SQLiteBackedActivityRepository()
        self.timelineLabelRepository = timelineLabelRepository ?? SQLiteBackedTimelineLabelRepository()
        self.calendarBoardStore = calendarBoardStore ?? CalendarBoardStore()
        self.appSettings = appSettings ?? AppSettings()
        self.pomodoroViewModel = pomodoroViewModel ?? PomodoroViewModel()
        self.dashboardViewModel = DashboardViewModel(
            activityTracker: self.activityTracker,
            insightEngine: self.insightEngine,
            activityRepository: self.activityRepository,
            timelineLabelRepository: self.timelineLabelRepository
        )
        self.lifecycleRecorder = ActivityLifecycleRecorder(repository: self.activityRepository)
        lifecycleRecorder.recordLaunch()
        installPersistenceLifecycleHandlers()
        installWidgetBoardChangeObserver()
        // Write a snapshot immediately at launch — CalendarBoardStore is already loaded from
        // disk at this point, so goalID/markerID are correct even before activity data loads.
        // This ensures the widget gallery shows live data regardless of window visibility.
        writeWidgetSnapshotNow()
    }

    deinit {
        if let widgetBoardChangeObserver {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                widgetBoardChangeObserver,
                CFNotificationName(ProductivityWidgetSnapshot.boardChangedNotificationName as CFString),
                nil
            )
        }
    }

    func writeWidgetSnapshotNow() {
        let isEnabled = UserDefaults.standard.bool(forKey: AppPreferenceKeys.isTrackingEnabled)
        ProductivityWidgetSnapshotWriter.update(
            from: dashboardViewModel,
            calendarBoardStore: calendarBoardStore,
            pomodoroViewModel: pomodoroViewModel,
            isTrackingEnabled: isEnabled
        )
    }

    #if DEBUG
    static func preview() -> AppEnvironment {
        AppEnvironment(
            activityTracker: MockActivityTracker(),
            activityRepository: InMemoryActivityRepository(),
            timelineLabelRepository: InMemoryTimelineLabelRepository(),
            calendarBoardStore: CalendarBoardStore(
                storeURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("ProductivityPreview-\(UUID().uuidString)", isDirectory: false)
                    .appendingPathExtension("calendarboard")
            )
        )
    }
    #endif

    private func installPersistenceLifecycleHandlers() {
        let repository = activityRepository
        let lifecycleRecorder = lifecycleRecorder
        let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter

        let workspaceNotifications: [Notification.Name] = [
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.willPowerOffNotification
        ]

        for notificationName in workspaceNotifications {
            lifecycleObservers.append(
                workspaceNotificationCenter.addObserver(
                    forName: notificationName,
                    object: NSWorkspace.shared,
                    queue: .main
                ) { [weak self] _ in
                    switch notificationName {
                    case NSWorkspace.willSleepNotification:
                        lifecycleRecorder.recordSystemWillSleep()
                    case NSWorkspace.screensDidSleepNotification,
                        NSWorkspace.sessionDidResignActiveNotification:
                        lifecycleRecorder.recordSystemWillSleep()
                    case NSWorkspace.didWakeNotification,
                        NSWorkspace.screensDidWakeNotification,
                        NSWorkspace.sessionDidBecomeActiveNotification:
                        lifecycleRecorder.recordSystemDidWake()
                        Task { @MainActor [weak self] in
                            self?.lifecycleRefreshID = UUID()
                        }
                    case NSWorkspace.willPowerOffNotification:
                        break
                    default:
                        break
                    }

                    Task {
                        try? await repository.flush()
                    }
                }
            )
        }

        // Refresh the widget snapshot whenever the app becomes active so the
        // widget gallery always shows current data.
        lifecycleObservers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.writeWidgetSnapshotNow()
                }
            }
        )
    }

    private func installWidgetBoardChangeObserver() {
        let observer = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())
        widgetBoardChangeObserver = observer

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let environment = Unmanaged<AppEnvironment>
                    .fromOpaque(observer)
                    .takeUnretainedValue()

                Task { @MainActor in
                    environment.calendarBoardStore.reloadFromDisk()
                    environment.writeWidgetSnapshotNow()
                }
            },
            ProductivityWidgetSnapshot.boardChangedNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    // Starts (or restarts) a persistent widget snapshot writer that survives window hide/show.
    // Called after the dashboard's persisted data has loaded so the first snapshot is complete.
    func startWidgetSync(isTrackingEnabled: Bool) {
        widgetSyncTask?.cancel()
        widgetSyncTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                ProductivityWidgetSnapshotWriter.update(
                    from: dashboardViewModel,
                    calendarBoardStore: calendarBoardStore,
                    pomodoroViewModel: pomodoroViewModel,
                    isTrackingEnabled: isTrackingEnabled
                )
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func reconcileTracking(isEnabled: Bool) async {
        desiredTrackingEnabled = isEnabled
        guard !isReconcilingTracking else { return }

        isReconcilingTracking = true
        defer { isReconcilingTracking = false }

        while true {
            let targetTrackingState = desiredTrackingEnabled

            if targetTrackingState {
                startTrackingIfNeeded()
            } else {
                await stopTracking()
            }

            guard desiredTrackingEnabled != targetTrackingState else { return }
        }
    }

    func startTrackingIfNeeded() {
        guard trackingTask == nil else { return }
        let taskID = UUID()
        trackingTaskID = taskID
        trackingTask = Task { [weak self] in
            guard let self else { return }
            await self.dashboardViewModel.startTracking(isEnabled: true)
            await MainActor.run { [weak self, taskID] in
                guard self?.trackingTaskID == taskID else { return }
                self?.trackingTask = nil
                self?.trackingTaskID = nil
            }
        }
    }

    func stopTracking(markAsPaused: Bool = true) async {
        guard trackingTask != nil || dashboardViewModel.trackingStatus != .paused else { return }
        trackingTaskID = nil
        trackingTask?.cancel()
        trackingTask = nil
        await dashboardViewModel.stopTracking(markAsPaused: markAsPaused)
    }

    func prepareForTermination() async {
        await stopTracking(markAsPaused: true)
        try? await activityRepository.flush()
    }

    func clearAllLocalData() async {
        let shouldResumeTracking = desiredTrackingEnabled || dashboardViewModel.trackingStatus != .paused
        await stopTracking(markAsPaused: true)
        await clearStoredLocalData()
        dashboardViewModel.resetActivityState()
        lifecycleRefreshID = UUID()

        if shouldResumeTracking {
            await reconcileTracking(isEnabled: true)
        }
    }

    func makeBackupSnapshot() async throws -> ProductivityBackupSnapshot {
        ProductivityBackupSnapshot(
            preferences: .current(),
            activitySegments: try await activityRepository.allSegments(),
            timelineLabelSegments: try await timelineLabelRepository.allLabelSegments(),
            manualEvents: ManualActivityEventStore.load(),
            appLabelRules: AppLabelRuleStore.load(),
            manualTrackingRules: AppLabelRuleStore.manualTrackingRules(),
            customActivityLabels: ActivityLabelCatalog.customDefinitions(),
            calendarGoals: calendarBoardStore.goals.map { goal in
                CalendarActivityGoalBackup(
                    id: goal.id,
                    name: goal.name,
                    markerID: goal.markerID,
                    symbol: goal.symbol,
                    targetCount: goal.targetCount,
                    period: goal.period.rawValue
                )
            },
            calendarPins: calendarBoardStore.pins,
            pomodoroConfiguration: PomodoroConfigurationBackup(
                focusMinutes: pomodoroViewModel.configuration.focusMinutes,
                shortBreakMinutes: pomodoroViewModel.configuration.shortBreakMinutes,
                longBreakMinutes: pomodoroViewModel.configuration.longBreakMinutes,
                sessionsBeforeLongBreak: pomodoroViewModel.configuration.sessionsBeforeLongBreak
            ),
            pomodoroSessionHistory: pomodoroViewModel.sessionHistory.map { record in
                PomodoroSessionRecordBackup(
                    id: record.id,
                    completedAt: record.completedAt,
                    focusMinutes: record.focusMinutes
                )
            }
        )
    }

    func restoreBackupSnapshot(_ snapshot: ProductivityBackupSnapshot) async throws {
        guard snapshot.schemaVersion <= ProductivityBackupSnapshot.currentSchemaVersion else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }

        await stopTracking(markAsPaused: true)
        await clearStoredLocalData()
        dashboardViewModel.resetActivityState()
        snapshot.preferences.apply()
        let shouldResumeTracking = snapshot.preferences.isTrackingEnabled
        desiredTrackingEnabled = shouldResumeTracking

        ActivityLabelCatalog.saveCustomDefinitions(snapshot.customActivityLabels)
        AppLabelRuleStore.save(snapshot.appLabelRules)
        AppLabelRuleStore.saveManualTrackingRules(snapshot.manualTrackingRules)
        ManualActivityEventStore.save(snapshot.manualEvents)
        calendarBoardStore.replaceGoals(snapshot.calendarGoals.map { goal in
            CalendarActivityGoal(
                id: goal.id,
                name: goal.name,
                markerID: goal.markerID,
                symbol: goal.symbol,
                targetCount: goal.targetCount,
                period: GoalPeriod(rawValue: goal.period) ?? .weekly
            )
        })
        calendarBoardStore.replacePins(snapshot.calendarPins)

        try await activityRepository.save(snapshot.activitySegments)
        try await activityRepository.flush()
        if let labelInterval = snapshot.timelineLabelSegments.restoreInterval {
            try await timelineLabelRepository.replaceLabelSegments(snapshot.timelineLabelSegments, in: labelInterval)
        }

        pomodoroViewModel.reset()
        pomodoroViewModel.configuration = PomodoroConfiguration(
            focusMinutes: snapshot.pomodoroConfiguration.focusMinutes,
            shortBreakMinutes: snapshot.pomodoroConfiguration.shortBreakMinutes,
            longBreakMinutes: snapshot.pomodoroConfiguration.longBreakMinutes,
            sessionsBeforeLongBreak: snapshot.pomodoroConfiguration.sessionsBeforeLongBreak
        )
        pomodoroViewModel.sessionHistory = snapshot.pomodoroSessionHistory
            .map { record in
                PomodoroSessionRecord(
                    id: record.id,
                    completedAt: record.completedAt,
                    focusMinutes: record.focusMinutes
                )
            }
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(365)
            .map { $0 }

        for event in snapshot.manualEvents {
            await ManualActivityEventNotificationScheduler.reschedule(event)
        }

        await dashboardViewModel.reloadPersistedSegments()
        lifecycleRefreshID = UUID()

        if shouldResumeTracking {
            await reconcileTracking(isEnabled: true)
        }
    }

    private func clearStoredLocalData() async {
        let manualEvents = ManualActivityEventStore.load()
        for event in manualEvents {
            ManualActivityEventNotificationScheduler.removeNotifications(for: event.id)
        }

        ManualActivityEventStore.clear()
        AppLabelRuleStore.clear()
        AppLabelRuleStore.saveManualTrackingRules([])
        ActivityLabelCatalog.clearCustomDefinitions()
        calendarBoardStore.clear()
        pomodoroViewModel.clearHistory()

        try? await activityRepository.deleteAllSegments()
        try? await timelineLabelRepository.deleteAllLabelSegments()
        try? await activityRepository.flush()
    }
}

private final class ActivityLifecycleRecorder: @unchecked Sendable {
    private enum DefaultsKey {
        static let systemSleepStartedAt = "lifecycle.systemSleepStartedAt"
    }

    private let repository: any ActivityRepository
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(repository: any ActivityRepository, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
    }

    func recordLaunch(at date: Date = Date()) {
        lock.withLock {
            let sleepStartedAt = defaults.object(forKey: DefaultsKey.systemSleepStartedAt) as? Date
            defaults.removeObject(forKey: DefaultsKey.systemSleepStartedAt)

            var segments: [ActivitySegment] = []

            if let sleepStartedAt, sleepStartedAt < date {
                segments.append(Self.sleepSegment(startDate: sleepStartedAt, endDate: date))
            }

            save(segments)
        }
    }

    func recordSystemWillSleep(at date: Date = Date()) {
        lock.withLock {
            guard defaults.object(forKey: DefaultsKey.systemSleepStartedAt) == nil else { return }
            defaults.set(date, forKey: DefaultsKey.systemSleepStartedAt)
        }
    }

    func recordSystemDidWake(at date: Date = Date()) {
        lock.withLock {
            guard let sleepStartedAt = defaults.object(forKey: DefaultsKey.systemSleepStartedAt) as? Date,
                  sleepStartedAt < date else {
                defaults.removeObject(forKey: DefaultsKey.systemSleepStartedAt)
                return
            }

            defaults.removeObject(forKey: DefaultsKey.systemSleepStartedAt)
            save([Self.sleepSegment(startDate: sleepStartedAt, endDate: date)])
        }
    }

    private func save(_ segments: [ActivitySegment]) {
        guard !segments.isEmpty else { return }
        let repository = repository
        Task {
            try? await repository.save(segments)
            try? await repository.flush()
        }
    }

    private static func sleepSegment(startDate: Date, endDate: Date) -> ActivitySegment {
        ActivitySegment(
            id: UUID(),
            appName: "macOS",
            bundleIdentifier: "productivity.lifecycle.sleep",
            title: "System Sleep",
            userDescription: "Mac was asleep; interactive activity tracking was paused",
            startDate: startDate,
            endDate: endDate,
            category: .system,
            label: .sleep,
            productivityScore: 0
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
