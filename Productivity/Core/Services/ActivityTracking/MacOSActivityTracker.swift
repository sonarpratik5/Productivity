@preconcurrency import AppKit
import CoreAudio
import CoreGraphics
import Foundation

@MainActor
final class MacOSActivityTracker: ActivityTracking {
    private let workspace: NSWorkspace
    private var classifier: any ActivityClassifying
    private let usesDefaultClassifier: Bool
    private let ignoredBundleIdentifier: String?
    private let snapshotInterval: Duration
    private let snapshotTolerance: Duration
    private let backgroundCompanionBundleIdentifiers: Set<String>
    private let ignoredWindowBundleIdentifiers: Set<String>
    private let minimumVisibleWindowArea: CGFloat
    private let minimumVisibleScreenShare: CGFloat
    private var observers: [NSObjectProtocol] = []
    private var liveUpdateTask: Task<Void, Never>?
    private var continuation: AsyncStream<[ActivitySegment]>.Continuation?
    private var activeApplication: NSRunningApplication?
    private var activeSegmentID = UUID()
    private var activeStartDate = Date()
    private var isInteractionSuspended = false
    private var backgroundSessions: [String: BackgroundCompanionSession] = [:]
    private var visibleWindowSessions: [String: VisibleWindowSession] = [:]
    private var recentActivationDates: [String: Date] = [:]
    private var labelRulesRevision = ""
    private var cachedTrackingMode: AppTrackingMode = .all
    private var cachedRules: [AppLabelRule] = []
    private var cachedManualTrackingRules: [AppLabelRule] = []
    private var segments: [ActivitySegment] = []

    nonisolated private static let defaultBackgroundCompanionBundleIdentifiers: Set<String> = [
        "com.apple.Music",
        "com.apple.podcasts",
        "com.apple.TV",
        "com.spotify.client",
        "com.colliderli.iina",
        "org.videolan.vlc"
    ]

    nonisolated private static let browserBundleIdentifiers: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "org.mozilla.firefox"
    ]

    nonisolated private static let safariAudioProcessBundleIdentifiers: Set<String> = [
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.GPU"
    ]

    nonisolated private static let systemSessionBundleIdentifiers: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        "com.apple.screensharing",
        "com.apple.RemoteDesktop"
    ]

    init(
        workspace: NSWorkspace = .shared,
        classifier: (any ActivityClassifying)? = nil,
        ignoredBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        snapshotInterval: Duration = .seconds(10),
        snapshotTolerance: Duration = .seconds(2),
        backgroundCompanionBundleIdentifiers: Set<String> = MacOSActivityTracker.defaultBackgroundCompanionBundleIdentifiers,
        ignoredWindowBundleIdentifiers: Set<String> = [
            // macOS system UI
            "com.apple.finder",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.systemuiserver",
            "com.apple.WindowManager",
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.Spotlight",
            "com.apple.systempreferences",
            "com.apple.SystemPreferences",
            // VPN and network utility apps
            "com.surfshark.SurfsharkVPN",
            "com.nordvpn.macos",
            "ch.protonvpn.mac",
            "net.mullvad.vpn",
            "com.privateinternetaccess.vpn",
            "com.expressvpnmac.expressvpn-ios-native",
            // Launcher apps
            "com.raycast.macos",
            "com.runningwithcrayons.Alfred",
            // Password managers
            "com.agilebits.onepassword7",
            "com.1password.1password",
            "com.bitwarden.desktop",
        ],
        minimumVisibleWindowArea: CGFloat = 90_000,
        minimumVisibleScreenShare: CGFloat = 0.035
    ) {
        self.workspace = workspace
        self.usesDefaultClassifier = classifier == nil
        self.classifier = classifier ?? RuleBasedActivityClassifier(selfBundleIdentifier: ignoredBundleIdentifier)
        self.ignoredBundleIdentifier = ignoredBundleIdentifier
        self.snapshotInterval = snapshotInterval
        self.snapshotTolerance = snapshotTolerance
        self.backgroundCompanionBundleIdentifiers = backgroundCompanionBundleIdentifiers
        self.ignoredWindowBundleIdentifiers = ignoredWindowBundleIdentifiers
        self.minimumVisibleWindowArea = minimumVisibleWindowArea
        self.minimumVisibleScreenShare = minimumVisibleScreenShare
    }

    var activitySegments: AsyncStream<[ActivitySegment]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(snapshotSegments(at: Date()))
        }
    }

    var currentSegments: [ActivitySegment] {
        snapshotSegments(at: Date())
    }

    var isCapturingLiveActivity: Bool {
        activeApplication != nil || !backgroundSessions.isEmpty || !visibleWindowSessions.isEmpty
    }

    func start() async {
        removeObserver()
        liveUpdateTask?.cancel()
        // Reset per-session state so segments never accumulate across stop/start cycles.
        // By the time start() is called again the previous session's segments have already
        // been published (publishStoredSegments in stop) and persisted by the dashboard
        // (currentSegments in stopTracking). Stale activation dates would incorrectly
        // qualify apps as visible companions in the new session.
        segments.removeAll()
        recentActivationDates.removeAll()
        activeApplication = trackedApplication(from: workspace.frontmostApplication)
        activeSegmentID = UUID()
        activeStartDate = Date()
        isInteractionSuspended = false
        refreshTrackingRuleCache(force: true)
        rememberActivation(for: activeApplication, at: activeStartDate)
        let backgroundBundleIdentifiers = syncBackgroundSessions(at: activeStartDate)
        syncVisibleWindowSessions(at: activeStartDate, excluding: backgroundBundleIdentifiers)
        installObservers()

        liveUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let (interval, tolerance) = self.currentSnapshotIntervalAndTolerance
                    try await Task.sleep(for: interval, tolerance: tolerance, clock: .suspending)
                } catch {
                    return
                }

                self.publishLiveSnapshot(at: Date())
            }
        }
    }

    func stop() async {
        let now = Date()
        closeCurrentSegment(at: now)
        closeStoppedBackgroundSessions(activeBundleIdentifiers: [], at: now)
        closeStoppedVisibleWindowSessions(activeBundleIdentifiers: [], at: now)
        activeApplication = nil
        isInteractionSuspended = false
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        removeObserver()
        publishStoredSegments()
        continuation?.finish()
        continuation = nil
    }

    private func handleActivation(_ notification: Notification) {
        guard let nextApplication = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        let now = Date()
        closeCurrentSegment(at: now)
        activeApplication = trackedApplication(from: nextApplication)
        activeSegmentID = UUID()
        activeStartDate = now
        isInteractionSuspended = false
        rememberActivation(for: activeApplication, at: now)
        let backgroundBundleIdentifiers = syncBackgroundSessions(at: now)
        syncVisibleWindowSessions(at: now, excluding: backgroundBundleIdentifiers)
        publishStoredSegments()
    }

    private func handleWorkspaceStateChange(_ notification: Notification) {
        let now = Date()

        switch notification.name {
        case NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.willPowerOffNotification:
            suspendInteractiveTracking(at: now)
            closeStoppedBackgroundSessions(activeBundleIdentifiers: [], at: now)
            publishStoredSegments()
        case NSWorkspace.screensDidSleepNotification:
            suspendInteractiveTracking(at: now)
            publishSnapshotWithoutIdleReconciliation(at: now)
        case NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification:
            resumeInteractiveTracking(at: now)
            publishSnapshotWithoutIdleReconciliation(at: now)
        case NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification:
            let backgroundBundleIdentifiers = syncBackgroundSessions(at: now)
            syncVisibleWindowSessions(at: now, excluding: backgroundBundleIdentifiers)
            publishLiveSnapshot(at: now)
        default:
            break
        }
    }

    private func trackedApplication(from application: NSRunningApplication?) -> NSRunningApplication? {
        guard let application else { return nil }
        // ignoredBundleIdentifier is still excluded from companion/window tracking,
        // but the app itself is a legitimate productive primary-attention target.
        guard !isSystemSessionApplication(application) else { return nil }
        guard isForegroundTrackableApplication(application) else { return nil }
        guard shouldTrack(application) else { return nil }
        return application
    }

    private func closeCurrentSegment(at endDate: Date) {
        guard let activeApplication, endDate > activeStartDate else { return }

        segments.append(makeSegment(for: activeApplication, id: activeSegmentID, startDate: activeStartDate, endDate: endDate))
    }

    private func publishStoredSegments() {
        continuation?.yield(segments)
    }

    private func publishLiveSnapshot(at date: Date) {
        reconcileIdleState(at: date)
        reconcileTrackingRules(at: date)
        publishSnapshotWithoutIdleReconciliation(at: date)
    }

    private func publishSnapshotWithoutIdleReconciliation(at date: Date) {
        let backgroundBundleIdentifiers = syncBackgroundSessions(at: date)
        syncVisibleWindowSessions(at: date, excluding: backgroundBundleIdentifiers)
        guard activeApplication != nil || !backgroundSessions.isEmpty || !visibleWindowSessions.isEmpty else { return }
        continuation?.yield(snapshotSegments(at: date))
    }

    private func snapshotSegments(at date: Date) -> [ActivitySegment] {
        var snapshot = segments

        if let activeApplication, date > activeStartDate {
            snapshot.append(makeSegment(
                for: activeApplication,
                id: activeSegmentID,
                startDate: activeStartDate,
                endDate: date
            ))
        }

        snapshot.append(contentsOf: backgroundSegments(at: date))
        snapshot.append(contentsOf: visibleWindowSegments(at: date))
        return snapshot
    }

    private func backgroundSegments(at date: Date) -> [ActivitySegment] {
        backgroundSessions.values.compactMap { session in
            guard date > session.startDate else {
                return nil
            }

            return makeSegment(for: session, endDate: date)
        }
    }

    private func visibleWindowSegments(at date: Date) -> [ActivitySegment] {
        visibleWindowSessions.values.compactMap { session in
            guard date > session.startDate else { return nil }
            return makeSegment(for: session, endDate: date)
        }
    }

    @discardableResult
    private func syncBackgroundSessions(at date: Date) -> Set<String> {
        let applications = backgroundApplications()
        let activeBundleIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        closeStoppedBackgroundSessions(activeBundleIdentifiers: activeBundleIdentifiers, at: date)

        for application in applications {
            guard
                let bundleIdentifier = application.bundleIdentifier,
                backgroundSessions[bundleIdentifier] == nil
            else {
                continue
            }

            backgroundSessions[bundleIdentifier] = BackgroundCompanionSession(
                id: UUID(),
                appName: application.localizedName ?? "Background App",
                bundleIdentifier: bundleIdentifier,
                startDate: date
            )
        }

        return activeBundleIdentifiers
    }

    private func syncVisibleWindowSessions(at date: Date, excluding backgroundBundleIdentifiers: Set<String>) {
        let visibleApplications = meaningfulVisibleApplications(excluding: backgroundBundleIdentifiers)
        let activeBundleIdentifiers = Set(visibleApplications.map(\.bundleIdentifier))
        closeStoppedVisibleWindowSessions(activeBundleIdentifiers: activeBundleIdentifiers, at: date)

        for visibleApplication in visibleApplications {
            guard visibleWindowSessions[visibleApplication.bundleIdentifier] == nil else {
                continue
            }

            visibleWindowSessions[visibleApplication.bundleIdentifier] = VisibleWindowSession(
                id: UUID(),
                appName: visibleApplication.appName,
                bundleIdentifier: visibleApplication.bundleIdentifier,
                startDate: date,
                visibleArea: visibleApplication.visibleArea
            )
        }
    }

    private func closeStoppedBackgroundSessions(activeBundleIdentifiers: Set<String>, at date: Date) {
        let stoppedBundleIdentifiers = Set(backgroundSessions.keys).subtracting(activeBundleIdentifiers)

        for bundleIdentifier in stoppedBundleIdentifiers {
            guard let session = backgroundSessions[bundleIdentifier] else {
                continue
            }

            if date > session.startDate {
                segments.append(makeSegment(for: session, endDate: date))
            }

            backgroundSessions.removeValue(forKey: bundleIdentifier)
        }
    }

    private func closeStoppedVisibleWindowSessions(activeBundleIdentifiers: Set<String>, at date: Date) {
        let stoppedBundleIdentifiers = Set(visibleWindowSessions.keys).subtracting(activeBundleIdentifiers)

        for bundleIdentifier in stoppedBundleIdentifiers {
            guard let session = visibleWindowSessions[bundleIdentifier] else {
                continue
            }

            if date > session.startDate {
                segments.append(makeSegment(for: session, endDate: date))
            }

            visibleWindowSessions.removeValue(forKey: bundleIdentifier)
        }
    }

    private func backgroundApplications() -> [NSRunningApplication] {
        let activeBundleIdentifier = activeApplication?.bundleIdentifier
        if let applicationsWithActiveAudioOutput = applicationsWithActiveAudioOutput(excluding: activeBundleIdentifier) {
            return applicationsWithActiveAudioOutput
        }

        return workspace.runningApplications.filter { application in
            guard let bundleIdentifier = application.bundleIdentifier else { return false }
            guard bundleIdentifier != ignoredBundleIdentifier else { return false }
            guard bundleIdentifier != activeBundleIdentifier else { return false }
            guard application.activationPolicy == .regular else { return false }
            guard backgroundCompanionBundleIdentifiers.contains(bundleIdentifier) else { return false }
            guard shouldTrack(application) else { return false }
            return !application.isTerminated
        }
    }

    private func applicationsWithActiveAudioOutput(excluding activeBundleIdentifier: String?) -> [NSRunningApplication]? {
        guard #available(macOS 15.0, *) else { return nil }

        let audioSystem = AudioHardwareSystem(id: AudioObjectID(kAudioObjectSystemObject))
        let runningApplications = workspace.runningApplications
        guard let activeAudioProcessBundleIdentifiers = activeAudioProcessBundleIdentifiers(from: audioSystem) else {
            return nil
        }
        var applications: [NSRunningApplication] = []

        for application in runningApplications {
            guard let bundleIdentifier = application.bundleIdentifier else { continue }
            guard bundleIdentifier != ignoredBundleIdentifier else { continue }
            guard bundleIdentifier != activeBundleIdentifier else { continue }
            guard application.activationPolicy == .regular else { continue }
            guard shouldTrack(application) else { continue }
            guard !application.isTerminated else { continue }
            guard isAudioOutputActive(
                for: application,
                activeAudioProcessBundleIdentifiers: activeAudioProcessBundleIdentifiers,
                audioSystem: audioSystem
            ) else { continue }

            applications.append(application)
        }

        return applications
    }

    @available(macOS 15.0, *)
    private func activeAudioProcessBundleIdentifiers(from audioSystem: AudioHardwareSystem) -> Set<String>? {
        guard let audioProcesses = try? audioSystem.processes else { return nil }

        return Set(audioProcesses.compactMap { audioProcess in
            guard (try? audioProcess.isRunningOutput) == true else { return nil }
            return try? audioProcess.bundleID
        })
    }

    @available(macOS 15.0, *)
    private func isAudioOutputActive(
        for application: NSRunningApplication,
        activeAudioProcessBundleIdentifiers: Set<String>,
        audioSystem: AudioHardwareSystem
    ) -> Bool {
        guard let bundleIdentifier = application.bundleIdentifier else { return false }

        if activeAudioProcessBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        if activeAudioProcessBundleIdentifiers.contains(where: { $0.hasPrefix(bundleIdentifier + ".") }) {
            return true
        }

        if bundleIdentifier == "com.apple.Safari"
            && !activeAudioProcessBundleIdentifiers.isDisjoint(with: Self.safariAudioProcessBundleIdentifiers) {
            return true
        }

        guard let audioProcess = try? audioSystem.process(for: application.processIdentifier) else {
            return false
        }

        return (try? audioProcess.isRunningOutput) == true
    }

    private func meaningfulVisibleApplications(excluding backgroundBundleIdentifiers: Set<String>) -> [VisibleWindowApplication] {
        let now = Date()
        pruneRecentActivations(at: now)
        let activeBundleIdentifier = activeApplication?.bundleIdentifier
        let trackingMode = cachedTrackingMode
        let labelRules = trackingMode == .manual ? cachedManualTrackingRules : []
        let screenArea = totalVisibleScreenArea()
        let areaThreshold = max(minimumVisibleWindowArea, screenArea * minimumVisibleScreenShare)
        var visibleAreasByBundleIdentifier: [String: VisibleWindowApplication] = [:]
        var applicationsByPID: [pid_t: NSRunningApplication] = [:]

        for windowInfo in visibleWindowInfo() {
            guard
                let layer = windowInfo[kCGWindowLayer as String] as? Int,
                layer == 0,
                (windowInfo[kCGWindowIsOnscreen as String] as? Bool) == true,
                let processIdentifier = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                let bounds = windowBounds(from: windowInfo),
                bounds.width >= 160,
                bounds.height >= 120
            else {
                continue
            }

            let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else { continue }

            let application: NSRunningApplication
            if let cached = applicationsByPID[processIdentifier] {
                application = cached
            } else if let found = NSRunningApplication(processIdentifier: processIdentifier) {
                applicationsByPID[processIdentifier] = found
                application = found
            } else {
                continue
            }

            guard
                let bundleIdentifier = application.bundleIdentifier,
                bundleIdentifier != ignoredBundleIdentifier,
                bundleIdentifier != activeBundleIdentifier,
                wasRecentlyActivated(bundleIdentifier: bundleIdentifier, at: now),
                !backgroundBundleIdentifiers.contains(bundleIdentifier),
                !ignoredWindowBundleIdentifiers.contains(bundleIdentifier),
                application.activationPolicy == .regular,
                !application.isHidden,
                !application.isTerminated,
                shouldTrack(
                    bundleIdentifier: bundleIdentifier,
                    appName: application.localizedName ?? "",
                    trackingMode: trackingMode,
                    labelRules: labelRules
                )
            else {
                continue
            }

            let appName = application.localizedName
                ?? windowInfo[kCGWindowOwnerName as String] as? String
                ?? "Visible App"
            let visibleArea = bounds.width * bounds.height
            guard visibleArea >= areaThreshold else { continue }

            if let existingApplication = visibleAreasByBundleIdentifier[bundleIdentifier] {
                visibleAreasByBundleIdentifier[bundleIdentifier] = VisibleWindowApplication(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    visibleArea: existingApplication.visibleArea + visibleArea
                )
            } else {
                visibleAreasByBundleIdentifier[bundleIdentifier] = VisibleWindowApplication(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    visibleArea: visibleArea
                )
            }
        }

        return visibleAreasByBundleIdentifier.values.sorted {
            if $0.visibleArea == $1.visibleArea {
                return $0.appName < $1.appName
            }

            return $0.visibleArea > $1.visibleArea
        }
    }

    private func rememberActivation(for application: NSRunningApplication?, at date: Date) {
        guard let bundleIdentifier = application?.bundleIdentifier else { return }
        recentActivationDates[bundleIdentifier] = date
        pruneRecentActivations(at: date)
    }

    private func wasRecentlyActivated(bundleIdentifier: String, at date: Date) -> Bool {
        guard let activationDate = recentActivationDates[bundleIdentifier] else { return false }
        return date.timeIntervalSince(activationDate) <= currentVisibleCompanionInteractionWindow
    }

    private func reconcileIdleState(at date: Date) {
        guard let anyInputEventType = CGEventType(rawValue: UInt32.max) else { return }
        let idleSeconds = TimeInterval(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType))

        if idleSeconds >= currentIdleTimeout {
            let lastInputDate = date.addingTimeInterval(-idleSeconds)
            let boundaryDate = max(activeStartDate, lastInputDate)
            suspendInteractiveTracking(at: boundaryDate)
        } else if isInteractionSuspended {
            resumeInteractiveTracking(at: date)
        }
    }

    private func reconcileTrackingRules(at date: Date) {
        guard refreshTrackingRuleCache() else { return }
        closeCurrentSegment(at: date)
        // Sync background sessions so any newly-excluded app is closed immediately.
        let backgroundBundleIdentifiers = syncBackgroundSessions(at: date)
        // Close all visible sessions — rules may have excluded some apps. Then
        // immediately re-sync so sessions that are still valid restart right away
        // rather than waiting until the next periodic tick.
        closeStoppedVisibleWindowSessions(activeBundleIdentifiers: [], at: date)
        activeApplication = trackedApplication(from: workspace.frontmostApplication)
        activeSegmentID = UUID()
        activeStartDate = date
        isInteractionSuspended = false
        rememberActivation(for: activeApplication, at: date)
        syncVisibleWindowSessions(at: date, excluding: backgroundBundleIdentifiers)
    }

    private func suspendInteractiveTracking(at date: Date) {
        closeCurrentSegment(at: date)
        closeStoppedVisibleWindowSessions(activeBundleIdentifiers: [], at: date)
        activeApplication = nil
        isInteractionSuspended = true
    }

    private func resumeInteractiveTracking(at date: Date) {
        activeApplication = trackedApplication(from: workspace.frontmostApplication)
        activeSegmentID = UUID()
        activeStartDate = date
        isInteractionSuspended = false
        rememberActivation(for: activeApplication, at: date)
        let backgroundBundleIdentifiers = syncBackgroundSessions(at: date)
        syncVisibleWindowSessions(at: date, excluding: backgroundBundleIdentifiers)
    }

    private func pruneRecentActivations(at date: Date) {
        recentActivationDates = recentActivationDates.filter { _, activationDate in
            date.timeIntervalSince(activationDate) <= currentVisibleCompanionInteractionWindow
        }
    }

    private var currentSnapshotIntervalAndTolerance: (Duration, Duration) {
        let seconds = max(5, Int(TrackingPreferences.snapshotIntervalSeconds()))
        return (.seconds(seconds), .seconds(max(1, min(5, seconds / 5))))
    }

    private var currentIdleTimeout: TimeInterval {
        TrackingPreferences.idleTimeoutSeconds()
    }

    private var currentVisibleCompanionInteractionWindow: TimeInterval {
        TrackingPreferences.visibleCompanionWindowSeconds()
    }

    private var currentLabelRulesRevision: String {
        let storedRevision = UserDefaults.standard.string(forKey: AppLabelRuleStore.revisionKey)
        return "\(AppLabelRuleStore.trackingMode().rawValue):\(storedRevision ?? "")"
    }

    private func visibleWindowInfo() -> [[String: Any]] {
        // This reads window-server metadata only; do not preflight or request
        // Screen Recording access unless future code captures pixels or titles.
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowInfo
    }

    private func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let bounds = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }

        guard
            let x = numberValue(for: "X", in: bounds),
            let y = numberValue(for: "Y", in: bounds),
            let width = numberValue(for: "Width", in: bounds),
            let height = numberValue(for: "Height", in: bounds)
        else {
            return nil
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func numberValue(for key: String, in dictionary: [String: Any]) -> CGFloat? {
        if let number = dictionary[key] as? NSNumber {
            return CGFloat(number.doubleValue)
        }

        return dictionary[key] as? CGFloat
    }

    private func totalVisibleScreenArea() -> CGFloat {
        let area = NSScreen.screens.reduce(CGFloat.zero) { totalArea, screen in
            totalArea + (screen.visibleFrame.width * screen.visibleFrame.height)
        }

        if area > 0 {
            return area
        }

        guard let mainScreen = NSScreen.main else {
            return 1
        }

        return mainScreen.visibleFrame.width * mainScreen.visibleFrame.height
    }

    private func shouldTrack(_ application: NSRunningApplication) -> Bool {
        guard !isSystemSessionApplication(application) else { return false }
        // Always track our own app regardless of mode — reviewing productivity is always productive.
        if let ignoredBundleIdentifier, application.bundleIdentifier == ignoredBundleIdentifier {
            return true
        }
        guard cachedTrackingMode == .manual else { return true }
        guard let bundleIdentifier = application.bundleIdentifier else { return false }
        let appName = application.localizedName ?? ""
        return shouldTrack(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            trackingMode: .manual,
            labelRules: cachedManualTrackingRules
        )
    }

    private func shouldTrack(
        bundleIdentifier: String,
        appName: String,
        trackingMode: AppTrackingMode,
        labelRules: [AppLabelRule]
    ) -> Bool {
        guard !Self.systemSessionBundleIdentifiers.contains(bundleIdentifier) else { return false }
        guard !appName.localizedCaseInsensitiveContains("loginwindow") else { return false }
        guard trackingMode == .manual else { return true }
        return AppLabelRuleStore.rule(for: bundleIdentifier, appName: appName, in: labelRules) != nil
    }

    private func isForegroundTrackableApplication(_ application: NSRunningApplication) -> Bool {
        Self.isForegroundTrackableActivationPolicy(
            application.activationPolicy,
            bundleIdentifier: application.bundleIdentifier,
            ignoredBundleIdentifier: ignoredBundleIdentifier
        )
    }

    nonisolated static func isForegroundTrackableActivationPolicy(
        _ activationPolicy: NSApplication.ActivationPolicy,
        bundleIdentifier: String?,
        ignoredBundleIdentifier: String?
    ) -> Bool {
        if let ignoredBundleIdentifier, bundleIdentifier == ignoredBundleIdentifier {
            return true
        }

        return activationPolicy == .regular
    }

    private func isSystemSessionApplication(_ application: NSRunningApplication) -> Bool {
        if let bundleIdentifier = application.bundleIdentifier,
           Self.systemSessionBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }

        let appName = application.localizedName ?? ""
        return appName.localizedCaseInsensitiveContains("loginwindow")
    }

    private func makeSegment(for activeApplication: NSRunningApplication, id: UUID, startDate: Date, endDate: Date) -> ActivitySegment {
        let appName = activeApplication.localizedName ?? "Unknown App"
        let bundleIdentifier = activeApplication.bundleIdentifier ?? "unknown.bundle"
        let label = classifier.label(for: bundleIdentifier, appName: appName)
        let category = label.category

        return ActivitySegment(
            id: id,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: appName,
            startDate: startDate,
            endDate: endDate,
            category: category,
            label: label,
            productivityScore: classifier.productivityScore(for: category)
        )
    }

    private func makeSegment(for session: BackgroundCompanionSession, endDate: Date) -> ActivitySegment {
        let classifiedLabel = classifier.label(for: session.bundleIdentifier, appName: session.appName)
        let label = labelForBackgroundCompanion(
            bundleIdentifier: session.bundleIdentifier,
            appName: session.appName,
            classifiedLabel: classifiedLabel
        )
        let category = label.category

        return ActivitySegment(
            id: session.id,
            appName: session.appName,
            bundleIdentifier: session.bundleIdentifier,
            title: session.appName,
            userDescription: "Background companion activity",
            startDate: session.startDate,
            endDate: endDate,
            category: category,
            label: label,
            productivityScore: classifier.productivityScore(for: category)
        )
    }

    private func labelForBackgroundCompanion(
        bundleIdentifier: String,
        appName: String,
        classifiedLabel: ActivityLabel
    ) -> ActivityLabel {
        guard Self.browserBundleIdentifiers.contains(bundleIdentifier) else {
            return classifiedLabel
        }

        let rules = cachedTrackingMode == .manual ? cachedManualTrackingRules : cachedRules
        guard AppLabelRuleStore.rule(for: bundleIdentifier, appName: appName, in: rules) == nil else {
            return classifiedLabel
        }

        return .unknown
    }

    @discardableResult
    private func refreshTrackingRuleCache(force: Bool = false) -> Bool {
        let revision = currentLabelRulesRevision
        guard force || revision != labelRulesRevision else { return false }
        labelRulesRevision = revision
        cachedTrackingMode = AppLabelRuleStore.trackingMode()
        cachedRules = AppLabelRuleStore.load()
        cachedManualTrackingRules = AppLabelRuleStore.manualTrackingRules()
        // Rebuild the default classifier with the freshly cached rules so segment
        // labelling stays consistent with shouldTrack decisions and avoids repeated
        // UserDefaults reads inside label(for:appName:) during segment creation.
        if usesDefaultClassifier {
            let activeRules = cachedTrackingMode == .manual ? cachedManualTrackingRules : cachedRules
            classifier = RuleBasedActivityClassifier(labelRules: activeRules, selfBundleIdentifier: ignoredBundleIdentifier)
        }
        return true
    }

    private func makeSegment(for session: VisibleWindowSession, endDate: Date) -> ActivitySegment {
        let label = classifier.label(for: session.bundleIdentifier, appName: session.appName)
        let category = label.category

        return ActivitySegment(
            id: session.id,
            appName: session.appName,
            bundleIdentifier: session.bundleIdentifier,
            title: session.appName,
            userDescription: "Visible companion activity",
            startDate: session.startDate,
            endDate: endDate,
            category: category,
            label: label,
            productivityScore: classifier.productivityScore(for: category)
        )
    }

    private func removeObserver() {
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }

        observers.removeAll()
    }

    private func installObservers() {
        let notificationNames: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.willPowerOffNotification
        ]

        observers = notificationNames.map { notificationName in
            workspace.notificationCenter.addObserver(
                forName: notificationName,
                object: workspace,
                queue: .main
            ) { [weak self] notification in
                MainActor.assumeIsolated {
                    if notification.name == NSWorkspace.didActivateApplicationNotification {
                        self?.handleActivation(notification)
                    } else {
                        self?.handleWorkspaceStateChange(notification)
                    }
                }
            }
        }
    }
}

private struct BackgroundCompanionSession {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let startDate: Date
}

private struct VisibleWindowSession {
    let id: UUID
    let appName: String
    let bundleIdentifier: String
    let startDate: Date
    let visibleArea: CGFloat
}

private struct VisibleWindowApplication {
    let appName: String
    let bundleIdentifier: String
    let visibleArea: CGFloat
}
