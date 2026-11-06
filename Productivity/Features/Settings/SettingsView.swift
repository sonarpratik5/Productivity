import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let segments: [ActivitySegment]

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.productivityTextScale) private var textScale
    @Environment(\.productivityIsFullScreen) private var isFullScreen
    @State private var selection: SettingsRoute = .general
    @State private var labelRules = AppLabelRuleStore.loadForSettings()
    @State private var isShowingDeleteAccountConfirmation = false
    @State private var isShowingClearDataConfirmation = false
    @State private var isExportingCSV = false
    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var isProcessingBackup = false
    @State private var backupDocument = ProductivityBackupDocument.empty
    @State private var csvDocument = ActivityCSVDocument(text: "")
    @State private var pendingRestoreSnapshot: ProductivityBackupSnapshot?
    @State private var isShowingRestoreBackupConfirmation = false
    @State private var featureNotice: FeatureNotice?
    @State private var installedApplications: [InstalledApplication] = []
    @State private var hasLoadedInstalledApplications = false
    @State private var isRefreshingApplications = false
    @State private var appSearchText = ""
    @State private var selectedAppBundleIdentifier = ""
    @State private var selectedAppLabel: ActivityLabel = .productive
    @State private var customLabelName = ""
    @State private var customLabelSystemImage = "tag.fill"
    @State private var customLabelSymbol = ""
    @State private var customLabelRollup: ActivityLabel = .productive
    @State private var isAddingTrackedApp = false
    @State private var isShowingOnlyUnknownApplications = true
    @State private var editingLabelID: String? = nil
    @State private var labelLibraryRevision: Int = 0
    @State private var launchAtLoginStatus = LaunchAtLoginStatus.current

    @AppStorage(AppPreferenceKeys.appearance) private var appearance = AppAppearance.system
    @AppStorage(AppTextSize.storageKey) private var textSize = AppTextSize.standard
    @AppStorage(ProductivityTheme.storageKey) private var theme = AppTheme.amethyst
    @AppStorage(AccountPreferenceKeys.displayName) private var displayName = AccountPreferenceKeys.defaultDisplayName
    @AppStorage(AppPreferenceKeys.isTrackingEnabled) private var isTrackingEnabled = true
    @AppStorage(AppLabelRuleStore.trackingModeKey) private var appTrackingMode = AppTrackingMode.all
    @AppStorage(TrackingPreferenceKeys.snapshotIntervalSeconds) private var snapshotIntervalSeconds = TrackingPreferences.recommendedSnapshotIntervalSeconds
    @AppStorage(TrackingPreferenceKeys.idleTimeoutSeconds) private var idleTimeoutSeconds = TrackingPreferences.recommendedIdleTimeoutSeconds
    @AppStorage(TrackingPreferenceKeys.visibleCompanionWindowSeconds) private var visibleCompanionWindowSeconds = TrackingPreferences.recommendedVisibleCompanionWindowSeconds
    @AppStorage(TrackingPreferenceKeys.timelineHorizonSeconds) private var timelineHorizonSeconds = TrackingPreferences.recommendedTimelineHorizonSeconds
    @AppStorage(TrackingPreferenceKeys.isTimelineEventContextOverlayEnabled) private var isTimelineEventContextOverlayEnabled = true
    @AppStorage(TrackingPreferenceKeys.isSleepHiddenInDayProgress) private var isSleepHiddenInDayProgress = true
    @AppStorage(NotificationPreferenceKeys.isPomodoroSoundEnabled) private var isPomodoroSoundEnabled = true
    @AppStorage(NotificationPreferenceKeys.pomodoroFocusStartSound) private var pomodoroFocusStartSound = PomodoroSoundEvent.focusStart.defaultSound.rawValue
    @AppStorage(NotificationPreferenceKeys.pomodoroShortBreakStartSound) private var pomodoroShortBreakStartSound = PomodoroSoundEvent.shortBreakStart.defaultSound.rawValue
    @AppStorage(NotificationPreferenceKeys.pomodoroLongBreakStartSound) private var pomodoroLongBreakStartSound = PomodoroSoundEvent.longBreakStart.defaultSound.rawValue
    @AppStorage(NotificationPreferenceKeys.pomodoroCompletionSound) private var pomodoroCompletionSound = PomodoroSoundEvent.completion.defaultSound.rawValue
    @AppStorage(AppPreferenceKeys.isDailyFocusHeaderEnabled) private var isDailyFocusHeaderEnabled = true
    @AppStorage(AppPreferenceKeys.customMotivationQuote) private var customMotivationQuote = ""
    @AppStorage(AppPreferenceKeys.productivityThresholdPercent) private var productivityThresholdPercent = 70

    init(segments: [ActivitySegment]) {
        self.segments = segments
    }

    fileprivate init(segments: [ActivitySegment], initialSelection: SettingsRoute) {
        self.segments = segments
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = SettingsLayoutMetrics(size: proxy.size, textScale: textScale, isFullScreen: isFullScreen)

            ScrollView {
                VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                    header(metrics: metrics)
                    settingsMenu(metrics: metrics)
                    selectedPage
                        .id(selection)
                        .dynamicTypeSize(metrics.dynamicTypeSize)
                        .controlSize(metrics.controlSize)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .frame(maxWidth: metrics.contentWidth, alignment: .leading)
                .padding(metrics.contentPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
        }
        .background(ProductivityTheme.background)
        .animation(.smooth(duration: 0.22), value: selection)
        .onAppear {
            applyAppearance(appearance)
            sanitizeTrackingPreferences()
            labelRules = AppLabelRuleStore.loadForSettings()
            refreshSystemIntegrationStatuses()
        }
        .onChange(of: selection) { _, newSelection in
            if newSelection == .labeling {
                loadInstalledApplicationsIfNeeded()
            }
        }
        .onChange(of: appearance) { _, newAppearance in
            applyAppearance(newAppearance)
        }
        .featureNotice($featureNotice)
        .fileExporter(
            isPresented: $isExportingCSV,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "productivity-activity.csv"
        ) { result in
            if case let .failure(error) = result {
                showIncompleteFeature("Could not save CSV: \(error.localizedDescription)")
            }
        }
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            if case let .failure(error) = result {
                showIncompleteFeature("Could not save backup: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importBackup(from: result)
        }
        .alert("Reset local profile?", isPresented: $isShowingDeleteAccountConfirmation) {
            Button("Reset", role: .destructive) {
                deleteLocalAccountState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears the local display name and pauses tracking on this Mac.")
        }
        .alert("Clear local activity data?", isPresented: $isShowingClearDataConfirmation) {
            Button("Clear", role: .destructive) {
                clearLocalDataState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears local activity history, timeline edits, manual events, app rules, calendar goals, pins, and Pomodoro history stored on this Mac.")
        }
        .alert("Restore backup?", isPresented: $isShowingRestoreBackupConfirmation) {
            Button("Restore", role: .destructive) {
                restorePendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingRestoreSnapshot = nil
            }
        } message: {
            Text(restoreConfirmationMessage)
        }
    }

    private func settingsMenu(metrics: SettingsLayoutMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SettingsRoute.allCases) { route in
                    SettingsMenuButton(
                        route: route,
                        isSelected: selection == route,
                        metrics: metrics
                    ) {
                        selection = route
                    }
                }
            }
            .padding(4)
        }
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }

    private func header(metrics: SettingsLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(selection.title)
                .font(ProductivityTypography.font(.hero, scale: metrics.titleFontSize / 34))
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text(selection.subtitle)
                .font(ProductivityTypography.font(.body, scale: metrics.subtitleFontSize / 15))
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
        case .general:
            generalPage
        case .privacy:
            privacyPage
        case .tracking:
            trackingPage
        case .pomodoro:
            pomodoroPage
        case .labeling:
            labelingPage
        case .account:
            accountPage
        }
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Appearance", systemImage: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title)
                                .tag(appearance)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360)

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Theme", selection: $theme) {
                            ForEach(AppTheme.allCases) { theme in
                                Text(theme.title)
                                    .tag(theme)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)

                        Text(theme.subtitle)
                            .productivityFont(.caption)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Text size", selection: $textSize) {
                            ForEach(AppTextSize.allCases) { size in
                                Text(size.title)
                                    .tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 420)

                        Text(textSize.subtitle)
                            .productivityFont(.caption)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsSection(title: "Startup", systemImage: "power") {
                launchAtLoginControl
            }

            SettingsSection(title: "Daily Quote", systemImage: "text.quote") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Show Daily Focus header", isOn: $isDailyFocusHeaderEnabled)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 360, alignment: .leading)

                    TextField("Use daily rotating quote", text: $customMotivationQuote, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .frame(maxWidth: 560)
                        .disabled(!isDailyFocusHeaderEnabled)

                    HStack(spacing: 12) {
                        Button {
                            customMotivationQuote = ""
                        } label: {
                            Label("Use Daily Rotation", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!isDailyFocusHeaderEnabled || customMotivationQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Text("Leave this empty to show a new built-in quote each day.")
                            .productivityFont(.caption)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                    }
                    .opacity(isDailyFocusHeaderEnabled ? 1 : 0.55)
                }
            }

            SettingsSection(title: "Dashboard", systemImage: "gauge.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        Text("Productivity threshold")
                            .productivityFont(.body)
                            .foregroundStyle(ProductivityTheme.textPrimary)
                        Spacer()
                        Text("\(productivityThresholdPercent)%")
                            .productivityFont(.bodyMonospaced)
                            .foregroundStyle(ProductivityTheme.accent)
                            .frame(minWidth: 42, alignment: .trailing)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(productivityThresholdPercent) },
                            set: { productivityThresholdPercent = Int($0) }
                        ),
                        in: 10...95,
                        step: 5
                    )
                    .frame(maxWidth: 420)
                    Text("The productivity % on Today turns teal above this level and coral below it.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Local Privacy", systemImage: "lock.shield") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Activity data is designed to stay local on this Mac. Export raw data when you want to inspect or back it up.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                    Text("FocusGrove does not record your screen or store screenshots. Visible-window detection uses macOS window metadata only.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                    Text("If macOS limits that metadata, foreground app, idle, background audio, manual events, Pomodoro, exports, and insights continue to work from local data.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }

            SettingsSection(title: "Local Data", systemImage: "externaldrive") {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            localDataButtons
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            localDataButtons
                        }
                    }

                    Text("CSV is for inspection. Backup export and restore use a lossless JSON snapshot of local app data.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var hasDayProgressSleepBoundary: Bool {
        segments.contains(where: \.isDayProgressSleepBoundary)
    }

    private var hideSleepFromDayProgressBinding: Binding<Bool> {
        Binding(
            get: { hasDayProgressSleepBoundary && isSleepHiddenInDayProgress },
            set: { isSleepHiddenInDayProgress = $0 }
        )
    }

    private var sleepProgressDetailText: String {
        hasDayProgressSleepBoundary
            ? "Sleep events stay saved and visible in your event history, but the day progress scale can focus on waking hours."
            : "Available after a sleep event exists for today."
    }

    private var trackingPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Tracking State", systemImage: "record.circle") {
                Toggle("Enable activity tracking", isOn: $isTrackingEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 360, alignment: .leading)
            }

            SettingsSection(title: "Timeline Display", systemImage: "timeline.selection") {
                VStack(alignment: .leading, spacing: 18) {
                    Toggle("Show event context overlay", isOn: $isTimelineEventContextOverlayEnabled)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 360, alignment: .leading)

                    Toggle("Hide Sleep from day progress", isOn: hideSleepFromDayProgressBinding)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 360, alignment: .leading)
                        .disabled(!hasDayProgressSleepBoundary)

                    Text(sleepProgressDetailText)
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TrackingOptionPicker(
                        title: "Timeline horizon",
                        detail: "Controls how much recent activity is visible in the live stream window.",
                        options: TrackingTuningOptions.timelineHorizons,
                        selection: $timelineHorizonSeconds
                    )
                }
            }

            SettingsSection(title: "Algorithm Tuning", systemImage: "dial.low") {
                VStack(alignment: .leading, spacing: 18) {
                    TrackingOptionPicker(
                        title: "Idle timeout",
                        detail: "Stops foreground reading/work when there has been no input.",
                        options: TrackingTuningOptions.idleTimeouts,
                        selection: $idleTimeoutSeconds
                    )

                    TrackingOptionPicker(
                        title: "Visible companion window",
                        detail: "Keeps recently used visible apps as context before treating them as stale.",
                        options: TrackingTuningOptions.visibleCompanionWindows,
                        selection: $visibleCompanionWindowSeconds
                    )

                    TrackingOptionPicker(
                        title: "Sampling cadence",
                        detail: "Controls how often the tracker refreshes windows and background audio.",
                        options: TrackingTuningOptions.snapshotIntervals,
                        selection: $snapshotIntervalSeconds
                    )
                }
            }

            SettingsSection(title: "Recommended Profile", systemImage: "checkmark.seal") {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Balanced is recommended", systemImage: "target")
                        .productivityFont(.bodyStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)

                    Text("Ten minutes is conservative enough to avoid marking slow reading as idle too quickly, while still catching attention drift. A 3 minute companion window and 10 second sample cadence keep background media and window changes fresh without heavy polling.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        idleTimeoutSeconds = TrackingPreferences.recommendedIdleTimeoutSeconds
                        visibleCompanionWindowSeconds = TrackingPreferences.recommendedVisibleCompanionWindowSeconds
                        snapshotIntervalSeconds = TrackingPreferences.recommendedSnapshotIntervalSeconds
                        timelineHorizonSeconds = TrackingPreferences.recommendedTimelineHorizonSeconds
                        isTimelineEventContextOverlayEnabled = true
                        isSleepHiddenInDayProgress = true
                    } label: {
                        Label("Restore Recommended", systemImage: "arrow.counterclockwise")
                    }
                }
            }
        }
    }

    private var pomodoroPage: some View {
        SettingsSection(title: "Sounds", systemImage: "speaker.wave.2") {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Play Pomodoro sounds", isOn: $isPomodoroSoundEnabled)
                    .toggleStyle(.switch)
                    .frame(maxWidth: 360, alignment: .leading)

                Label("Procedural tones are generated locally by the app, so they do not depend on bundled or licensed audio files.", systemImage: "waveform")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)

                VStack(spacing: 10) {
                    PomodoroSoundSettingRow(
                        title: "Focus start",
                        detail: "Plays when a focus session begins.",
                        selection: $pomodoroFocusStartSound
                    )
                    PomodoroSoundSettingRow(
                        title: "Short break start",
                        detail: "Plays when a short break begins.",
                        selection: $pomodoroShortBreakStartSound
                    )
                    PomodoroSoundSettingRow(
                        title: "Long break start",
                        detail: "Plays when a long break begins.",
                        selection: $pomodoroLongBreakStartSound
                    )
                    PomodoroSoundSettingRow(
                        title: "Timer finish",
                        detail: "Plays at natural phase completion before the next phase starts.",
                        selection: $pomodoroCompletionSound
                    )
                }
                .disabled(!isPomodoroSoundEnabled)
                .opacity(isPomodoroSoundEnabled ? 1 : 0.55)

                Text("Timing controls stay on the Pomodoro page so the timer can be adjusted in context.")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }
        }
    }

    private var labelingPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSection(title: "Tracking Mode", systemImage: "scope") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose how app activity enters your timeline. Manual mode only tracks apps you explicitly add here.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Tracking mode", selection: $appTrackingMode) {
                        ForEach(AppTrackingMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                }
            }

            SettingsSection(title: "Label Library", systemImage: "tag") {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Labels are shared across app rules, manual events, timeline edits, analytics, and insights.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(ActivityLabel.commonLabels) { rollup in
                            LabelLibraryGroup(
                                rollup: rollup,
                                labels: labels(forRollup: rollup),
                                editingLabelID: editingLabelID,
                                onStartEdit: { label in editingLabelID = label.id },
                                onSave: { label, name, newRollup in
                                    saveCustomLabelEdit(label: label, newName: name, newRollup: newRollup)
                                },
                                onDelete: { label in deleteCustomLabel(label) },
                                onCancelEdit: { editingLabelID = nil }
                            )
                        }
                    }
                    .id(labelLibraryRevision)

                    Divider()
                        .background(ProductivityTheme.border.opacity(0.32))

                    customLabelCreator
                }
            }

            SettingsSection(title: "Unknown Apps", systemImage: "questionmark.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Apps with unresolved labels stay Unknown until you classify them. Review the most common ones here.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Show only currently unknown apps", isOn: $isShowingOnlyUnknownApplications)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: 320, alignment: .leading)

                    if reviewableUnknownApplications.isEmpty {
                        Text("No unknown tracked apps need review right now.")
                            .productivityFont(.body)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(ProductivityTheme.subtleBackground.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(reviewableUnknownApplications.prefix(12)) { application in
                                TrackedAppRuleRow(
                                    rule: reviewRule(for: application),
                                    detail: unknownApplicationDetail(for: application),
                                    showsRemoveButton: false
                                ) { label in
                                    setRule(for: application.installedApplication, label: label)
                                } onRemove: {}
                            }
                        }
                    }
                }
            }

            if appTrackingMode == .manual {
                SettingsSection(title: "Manual Tracking", systemImage: "list.bullet") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Text("Only apps added here will appear in your activity timeline.")
                                .productivityFont(.caption)
                                .foregroundStyle(ProductivityTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 12)

                            Button {
                                withAnimation(.smooth(duration: 0.2)) {
                                    isAddingTrackedApp.toggle()
                                    if !isAddingTrackedApp {
                                        resetAddAppForm()
                                    }
                                }
                            } label: {
                                Label(isAddingTrackedApp ? "Cancel" : "Add App", systemImage: isAddingTrackedApp ? "xmark" : "plus")
                            }
                        }

                        if isAddingTrackedApp {
                            addTrackedApplicationPanel
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        trackedApplicationsList
                    }
                }
            } else {
                SettingsSection(title: "App Rules", systemImage: "sparkle.magnifyingglass") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Foreground apps are classified with defaults and your saved labels.")
                            .productivityFont(.caption)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        automaticApplicationsList
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: labelRules)
        .animation(.smooth(duration: 0.22), value: appTrackingMode)
        .onChange(of: labelRules) { _, rules in
            saveCurrentLabelRules(rules)
        }
        .onChange(of: appTrackingMode) { _, mode in
            AppLabelRuleStore.bumpRevision()
            if mode == .all {
                labelRules = AppLabelRuleStore.load()
                appSearchText = ""
                selectedAppBundleIdentifier = ""
                isAddingTrackedApp = false
            } else {
                labelRules = AppLabelRuleStore.manualTrackingRules()
                resetAddAppForm()
            }
        }
        .onAppear {
            loadInstalledApplicationsIfNeeded()
        }
    }

    private var accountPage: some View {
        SettingsSection(title: "Profile", systemImage: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Display name", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        isShowingDeleteAccountConfirmation = true
                    } label: {
                        Label("Reset Local Profile", systemImage: "trash")
                    }

                    Text("Only local profile details live here for now.")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
            }
        }
    }

    private var launchAtLoginControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    Toggle("Launch FocusGrove at login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .frame(maxWidth: 360, alignment: .leading)

                    launchAtLoginStatusBadge
                    Spacer(minLength: 12)
                    openLoginItemsButton
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Launch FocusGrove at login", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                    launchAtLoginStatusBadge
                    openLoginItemsButton
                }
            }

            Text(launchAtLoginStatus.detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            launchAtLoginStatus.isToggleOn
        } set: { isEnabled in
            setLaunchAtLogin(isEnabled)
        }
    }

    private var launchAtLoginStatusBadge: some View {
        Label(launchAtLoginStatus.title, systemImage: launchAtLoginStatus.systemImage)
            .productivityFont(.captionStrong)
            .foregroundStyle(launchAtLoginStatus.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(launchAtLoginStatus.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
    }

    private var openLoginItemsButton: some View {
        Button {
            SMAppService.openSystemSettingsLoginItems()
            refreshSystemIntegrationStatuses()
        } label: {
            Label("Open Login Items", systemImage: "gearshape")
        }
        .buttonStyle(.borderless)
    }

    private var localDataButtons: some View {
        Group {
            Button {
                exportCSV()
            } label: {
                Label("Export CSV", systemImage: "tablecells")
            }
            .disabled(isProcessingBackup)

            Button {
                exportBackup()
            } label: {
                Label("Export Backup", systemImage: "archivebox")
            }
            .disabled(isProcessingBackup)

            Button {
                isImportingBackup = true
            } label: {
                Label("Restore Backup", systemImage: "arrow.down.doc")
            }
            .disabled(isProcessingBackup)

            Button(role: .destructive) {
                isShowingClearDataConfirmation = true
            } label: {
                Label("Clear Local Data", systemImage: "xmark.bin")
            }
            .disabled(isProcessingBackup)
        }
    }

    private var backupFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "productivity-backup-\(formatter.string(from: Date())).json"
    }

    private var restoreConfirmationMessage: String {
        guard let pendingRestoreSnapshot else {
            return "This replaces local FocusGrove data with the selected backup."
        }

        return """
        This replaces local FocusGrove data with the selected backup.

        Backup contains \(pendingRestoreSnapshot.activitySegments.count) activity segments, \(pendingRestoreSnapshot.manualEvents.count) manual events, \(pendingRestoreSnapshot.calendarGoals.count) goals, and \(pendingRestoreSnapshot.pomodoroSessionHistory.count) Pomodoro sessions.
        """
    }

    private func exportCSV() {
        isProcessingBackup = true
        Task {
            do {
                let exportSegments = try await environment.activityRepository.allSegments()
                csvDocument = ActivityCSVExporter.document(for: exportSegments)
                isExportingCSV = true
            } catch {
                showIncompleteFeature("Could not prepare CSV: \(error.localizedDescription)")
            }
            isProcessingBackup = false
        }
    }

    private var customLabelCreator: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                CustomLabelPreviewGlyph(
                    symbol: customLabelSymbol.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    systemImage: customLabelSystemImage,
                    tint: customLabelTint
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("New custom label")
                        .productivityFont(.captionStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text("The color follows the rollup so app lists and charts stay consistent.")
                        .productivityFont(.note)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Spacer(minLength: 12)
                createCustomLabelButton
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Name")
                    .productivityFont(.note)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                TextField("Deep Work", text: $customLabelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Rollup")
                    .productivityFont(.note)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                Picker("Rollup", selection: $customLabelRollup) {
                    ForEach(ActivityLabel.commonLabels) { label in
                        Text(label.title).tag(label)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
            }

            HStack(alignment: .bottom, spacing: 12) {
                labeledControl("Emoji") {
                    TextField("Emoji", text: $customLabelSymbol)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 78)
                }
                labeledControl("Icon") {
                    Picker("Icon", selection: $customLabelSystemImage) {
                        ForEach(customLabelIconChoices, id: \.self) { systemImage in
                            Label(systemImage, systemImage: systemImage).tag(systemImage)
                        }
                    }
                    .frame(width: 155)
                }
            }
        }
        .padding(14)
        .background(ProductivityTheme.elevatedBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(customLabelTint.opacity(0.24), lineWidth: 1)
        )
    }

    private func labeledControl<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .productivityFont(.note)
                .foregroundStyle(ProductivityTheme.textSecondary)
            content()
        }
    }

    private var createCustomLabelButton: some View {
        Button {
            let label = ActivityLabelCatalog.addCustomLabel(
                title: customLabelName,
                systemImage: customLabelSystemImage,
                symbol: customLabelSymbol,
                tint: ActivityLabelColor(rollup: customLabelRollup),
                rollup: customLabelRollup
            )
            selectedAppLabel = label
            resetCustomLabelForm()
        } label: {
            Label("Create", systemImage: "plus")
        }
        .disabled(customLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var customLabelTint: Color {
        ActivityLabelColor(rollup: customLabelRollup).color
    }

    private func labels(forRollup rollup: ActivityLabel) -> [ActivityLabel] {
        ActivityLabel.allCases.filter { $0.commonRollup == rollup.commonRollup }
    }


    private var customLabelIconChoices: [String] {
        ["tag.fill", "star.fill", "scope", "paintpalette.fill", "sun.max.fill", "moon.zzz.fill", "heart.fill", "figure.run", "book.closed.fill", "briefcase.fill"]
    }

    private func resetCustomLabelForm() {
        customLabelName = ""
        customLabelSystemImage = "tag.fill"
        customLabelSymbol = ""
        customLabelRollup = .productive
    }

    private func saveCustomLabelEdit(label: ActivityLabel, newName: String, newRollup: ActivityLabel) {
        if case .custom = label {
            var definitions = ActivityLabelCatalog.customDefinitions()
            guard let index = definitions.firstIndex(where: { $0.id == label.id }) else { return }
            let existing = definitions[index]
            definitions[index] = ActivityLabelDefinition(
                id: existing.id,
                title: newName,
                systemImage: existing.systemImage,
                symbol: existing.symbol,
                tint: ActivityLabelColor(rollup: newRollup),
                rollup: newRollup.commonRollup
            )
            ActivityLabelCatalog.saveCustomDefinitions(definitions)
        } else {
            ActivityLabelCatalog.saveBuiltinRollupOverride(for: label.id, rollup: newRollup)
        }
        editingLabelID = nil
        labelLibraryRevision += 1
    }

    private func deleteCustomLabel(_ label: ActivityLabel) {
        var definitions = ActivityLabelCatalog.customDefinitions()
        definitions.removeAll { $0.id == label.id }
        ActivityLabelCatalog.saveCustomDefinitions(definitions)
        labelLibraryRevision += 1
    }


    private var automaticApplicationsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Application labels")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                Spacer()
                if isRefreshingApplications {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        refreshInstalledApplications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .help("Refresh installed applications")
                }
                Text("\(filteredAutomaticApplications.count) apps")
                    .productivityFont(.captionMonospaced)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            TextField("Search applications", text: $appSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

            LazyVStack(spacing: 8) {
                ForEach(labelRuleSections(from: Array(filteredAutomaticRules.prefix(80)))) { section in
                    LabelRuleGroupHeader(rollup: section.rollup, count: section.rules.count)

                    ForEach(section.rules, id: \.displayIdentity) { rule in
                        TrackedAppRuleRow(
                            rule: rule,
                            detail: "Tracked in All Apps mode",
                            showsRemoveButton: false
                        ) { label in
                            setRule(for: rule, label: label)
                        } onRemove: {
                        }
                    }
                }
            }
        }
    }


    private var addTrackedApplicationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Find an app")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                Spacer()
                if selectedApplication != nil {
                    selectedLabel
                } else if isRefreshingApplications {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        refreshInstalledApplications()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .help("Refresh installed applications")
                }
            }

            TextField("Search applications", text: $appSearchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

            if let selectedApplication {
                selectedApplicationCard(selectedApplication)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        newLabelPicker
                        addSelectedApplicationButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        newLabelPicker
                        addSelectedApplicationButton
                    }
                }
            } else {
                applicationSearchResults
            }
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
        )
    }

    private var applicationSearchResults: some View {
        VStack(spacing: 6) {
            if appSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Search for an installed app to add it.")
                    .productivityFont(.body)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else if addableInstalledApplications.isEmpty {
                Text("No matching apps found.")
                    .productivityFont(.body)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            } else {
                ForEach(addableInstalledApplications.prefix(8)) { application in
                    Button {
                        selectedAppBundleIdentifier = application.bundleIdentifier
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "app")
                                .foregroundStyle(ProductivityTheme.accent)
                                .frame(width: 28, height: 28)
                                .background(ProductivityTheme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 7))

                            Text(application.name)
                                .productivityFont(.bodyMedium)
                                .foregroundStyle(ProductivityTheme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Image(systemName: "plus")
                                .productivityFont(.captionStrong)
                                .foregroundStyle(ProductivityTheme.textSecondary)
                        }
                        .padding(10)
                        .background(ProductivityTheme.elevatedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: 620)
    }

    private var newLabelPicker: some View {
        Picker("Activity label", selection: $selectedAppLabel) {
            ForEach(ActivityLabel.allCases) { label in
                Text(label.title).tag(label)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 220)
    }

    private var addSelectedApplicationButton: some View {
        Button {
            addSelectedApplication()
        } label: {
            Label("Add", systemImage: "plus")
        }
        .disabled(selectedAppBundleIdentifier.isEmpty)
    }

    private var selectedLabel: some View {
        Text("Selected")
            .productivityFont(.captionStrong)
            .foregroundStyle(ProductivityTheme.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ProductivityTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private func selectedApplicationCard(_ application: InstalledApplication) -> some View {
        HStack(spacing: 10) {
            ActivityLabelGlyph(label: selectedAppLabel, size: 30, iconSize: 14, isSelected: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)
                Text("Choose the label this app should use in streams, analytics, and insights.")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                selectedAppBundleIdentifier = ""
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Choose another app")
        }
        .padding(12)
        .frame(maxWidth: 620)
        .background(ProductivityTheme.elevatedBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectedAppLabel.tint.opacity(0.26), lineWidth: 1)
        )
    }

    private var trackedApplicationsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Tracked applications")
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                Spacer()
                Text("\(activeLabelRules.count)")
                    .productivityFont(.captionMonospaced)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            if activeLabelRules.isEmpty {
                Text("No apps are tracked in Manual mode yet.")
                    .productivityFont(.body)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ProductivityTheme.subtleBackground.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(labelRuleSections(from: activeLabelRules)) { section in
                        LabelRuleGroupHeader(rollup: section.rollup, count: section.rules.count)

                        ForEach(section.rules, id: \.displayIdentity) { rule in
                            TrackedAppRuleRow(rule: rule) { label in
                                updateRule(rule, label: label)
                            } onRemove: {
                                removeRule(rule)
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeLabelRules: [AppLabelRule] {
        sortedLabelRules(labelRules.filter(\.isEnabled))
    }

    private var labelRuleLookup: [String: AppLabelRule] {
        Dictionary(labelRules.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var installedApplicationLookup: [String: InstalledApplication] {
        Dictionary(installedApplications.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var filteredAutomaticApplications: [InstalledApplication] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return installedApplications }

        return installedApplications.filter { application in
            application.matches(query)
        }
    }

    private var filteredAutomaticRules: [AppLabelRule] {
        displayRules(for: filteredAutomaticApplications)
    }

    private var selectedApplication: InstalledApplication? {
        installedApplicationLookup[selectedAppBundleIdentifier]
    }

    private var addableInstalledApplications: [InstalledApplication] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trackedBundleIdentifiers = Set(labelRules.lazy.filter(\.isEnabled).map(\.bundleIdentifier))
        let applications = installedApplications.filter { application in
            !trackedBundleIdentifiers.contains(application.bundleIdentifier)
        }

        guard !query.isEmpty else { return applications }
        return applications.filter { application in
            application.matches(query)
        }
    }

    private var reviewableUnknownApplications: [UnknownApplicationSummary] {
        let applicationLookup = installedApplicationLookup
        let rulesByBundleIdentifier = labelRuleLookup
        let classifier = RuleBasedActivityClassifier(labelRules: labelRules)
        let summaries = Dictionary(grouping: segments.filter { segment in
            segment.category == .unknown
                && !segment.isLifecycleContext
                && !segment.isManualEventContext
                && !segment.bundleIdentifier.isEmpty
        }, by: \.bundleIdentifier)
        .compactMap { bundleIdentifier, groupedSegments -> UnknownApplicationSummary? in
            guard let firstSegment = groupedSegments.first else { return nil }
            let application = applicationLookup[bundleIdentifier]
                ?? InstalledApplication(name: firstSegment.appName, bundleIdentifier: bundleIdentifier)
            let totalDuration = groupedSegments.reduce(0) { $0 + $1.duration }
            return UnknownApplicationSummary(
                installedApplication: application,
                totalDuration: totalDuration,
                occurrenceCount: groupedSegments.count
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalDuration == rhs.totalDuration {
                return lhs.installedApplication.name.localizedCaseInsensitiveCompare(rhs.installedApplication.name) == .orderedAscending
            }

            return lhs.totalDuration > rhs.totalDuration
        }

        guard isShowingOnlyUnknownApplications else { return summaries }
        return summaries.filter { summary in
            displayRule(
                for: summary.installedApplication,
                rulesByBundleIdentifier: rulesByBundleIdentifier,
                classifier: classifier
            ).label == .unknown
        }
    }

    private func rule(for application: InstalledApplication) -> AppLabelRule? {
        labelRuleLookup[application.bundleIdentifier]
    }

    private func displayRules(for applications: [InstalledApplication]) -> [AppLabelRule] {
        let rulesByBundleIdentifier = labelRuleLookup
        let classifier = RuleBasedActivityClassifier(labelRules: labelRules)
        return sortedLabelRules(applications.map { application in
            displayRule(
                for: application,
                rulesByBundleIdentifier: rulesByBundleIdentifier,
                classifier: classifier
            )
        })
    }

    private func displayRule(
        for application: InstalledApplication,
        rulesByBundleIdentifier: [String: AppLabelRule],
        classifier: RuleBasedActivityClassifier
    ) -> AppLabelRule {
        if let rule = rulesByBundleIdentifier[application.bundleIdentifier] {
            return rule
        }

        let label = classifier.label(
            for: application.bundleIdentifier,
            appName: application.name
        )
        return AppLabelRule(
            appName: application.name,
            bundleIdentifier: application.bundleIdentifier,
            label: label
        )
    }

    private func displayRule(for application: InstalledApplication) -> AppLabelRule {
        displayRule(
            for: application,
            rulesByBundleIdentifier: labelRuleLookup,
            classifier: RuleBasedActivityClassifier(labelRules: labelRules)
        )
    }

    private func reviewRule(for application: UnknownApplicationSummary) -> AppLabelRule {
        displayRule(for: application.installedApplication)
    }

    private func unknownApplicationDetail(for application: UnknownApplicationSummary) -> String {
        "\(DurationFormatting.abbreviated(application.totalDuration)) across \(application.occurrenceCount) clips"
    }

    private func addSelectedApplication() {
        guard let application = installedApplications.first(where: { $0.bundleIdentifier == selectedAppBundleIdentifier }) else { return }
        setRule(for: application, label: selectedAppLabel)
        resetAddAppForm()
        isAddingTrackedApp = false
    }

    private func setRule(for application: InstalledApplication, label: ActivityLabel) {
        if let index = labelRules.firstIndex(where: { $0.bundleIdentifier == application.bundleIdentifier }) {
            labelRules[index].label = label
            labelRules[index].isEnabled = true
        } else {
            labelRules.append(AppLabelRule(
                appName: application.name,
                bundleIdentifier: application.bundleIdentifier,
                label: label
            ))
        }

        saveCurrentLabelRules()
    }

    private func setRule(for rule: AppLabelRule, label: ActivityLabel) {
        if let application = installedApplications.first(where: { $0.bundleIdentifier == rule.bundleIdentifier }) {
            setRule(for: application, label: label)
        } else {
            setRule(
                for: InstalledApplication(name: rule.appName, bundleIdentifier: rule.bundleIdentifier),
                label: label
            )
        }
    }

    private func updateRule(_ rule: AppLabelRule, label: ActivityLabel) {
        guard let index = labelRules.firstIndex(where: { $0.id == rule.id }) else { return }
        labelRules[index].label = label
        saveCurrentLabelRules()
    }

    private func removeRule(_ rule: AppLabelRule) {
        labelRules.removeAll { $0.id == rule.id }
        saveCurrentLabelRules()
    }

    private func resetAddAppForm() {
        selectedAppBundleIdentifier = ""
        selectedAppLabel = .productive
        appSearchText = ""
    }

    private func saveCurrentLabelRules(_ rules: [AppLabelRule]? = nil) {
        let rulesToSave = rules ?? labelRules
        if appTrackingMode == .manual {
            AppLabelRuleStore.saveManualTrackingRules(rulesToSave)
        } else {
            AppLabelRuleStore.save(rulesToSave)
        }
    }

    private func labelRuleSections(from rules: [AppLabelRule]) -> [LabelRuleSection] {
        ActivityLabel.commonLabels.compactMap { rollup in
            let sectionRules = rules.filter { $0.label.commonRollup == rollup.commonRollup }
            guard !sectionRules.isEmpty else { return nil }
            return LabelRuleSection(rollup: rollup, rules: sectionRules)
        }
    }

    private func sortedLabelRules(_ rules: [AppLabelRule]) -> [AppLabelRule] {
        rules.sorted { lhs, rhs in
            let lhsGroup = labelSortIndex(lhs.label)
            let rhsGroup = labelSortIndex(rhs.label)
            if lhsGroup != rhsGroup {
                return lhsGroup < rhsGroup
            }

            let labelOrder = lhs.label.title.localizedCaseInsensitiveCompare(rhs.label.title)
            if labelOrder != .orderedSame {
                return labelOrder == .orderedAscending
            }

            return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
        }
    }

    private func labelSortIndex(_ label: ActivityLabel) -> Int {
        switch label.commonRollup {
        case .productive: 0
        case .unproductive: 1
        case .unknown: 2
        default: 3
        }
    }

    private func deleteLocalAccountState() {
        displayName = ""
        isTrackingEnabled = false
    }

    private func clearLocalDataState() {
        labelRules = []
        appTrackingMode = .all
        Task {
            await environment.clearAllLocalData()
            labelRules = AppLabelRuleStore.loadForSettings()
        }
    }

    private func exportBackup() {
        isProcessingBackup = true
        Task {
            do {
                let snapshot = try await environment.makeBackupSnapshot()
                backupDocument = try ProductivityBackupDocument(snapshot: snapshot)
                isExportingBackup = true
            } catch {
                showIncompleteFeature("Could not prepare backup: \(error.localizedDescription)")
            }
            isProcessingBackup = false
        }
    }

    private func importBackup(from result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            pendingRestoreSnapshot = try ProductivityBackupSnapshot.decode(from: url)
            isShowingRestoreBackupConfirmation = true
        } catch {
            pendingRestoreSnapshot = nil
            showIncompleteFeature("Could not read backup: \(error.localizedDescription)")
        }
    }

    private func restorePendingBackup() {
        guard let snapshot = pendingRestoreSnapshot else { return }
        isProcessingBackup = true
        Task {
            do {
                try await environment.restoreBackupSnapshot(snapshot)
                pendingRestoreSnapshot = nil
                labelRules = AppLabelRuleStore.loadForSettings()
                let restoredAppearance = AppAppearance(
                    rawValue: UserDefaults.standard.string(forKey: AppPreferenceKeys.appearance) ?? ""
                ) ?? .system
                environment.appSettings.appearance = restoredAppearance
                showIncompleteFeature("Backup restored.")
            } catch {
                showIncompleteFeature("Could not restore backup: \(error.localizedDescription)")
            }
            isProcessingBackup = false
        }
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshSystemIntegrationStatuses()

            if launchAtLoginStatus == .requiresApproval {
                showIncompleteFeature("Approve FocusGrove in System Settings > General > Login Items.")
            }
        } catch {
            refreshSystemIntegrationStatuses()
            showIncompleteFeature("Could not update Launch at Login: \(error.localizedDescription)")
        }
    }

    private func refreshSystemIntegrationStatuses() {
        launchAtLoginStatus = .current
    }

    private func showIncompleteFeature(_ message: String) {
        featureNotice = .incomplete(message)
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                if featureNotice?.message == message {
                    featureNotice = nil
                }
            }
        }
    }

    private func applyAppearance(_ appearance: AppAppearance) {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    private func loadInstalledApplicationsIfNeeded() {
        guard !hasLoadedInstalledApplications else { return }
        hasLoadedInstalledApplications = true
        runApplicationScan()
    }

    private func refreshInstalledApplications() {
        guard !isRefreshingApplications else { return }
        isRefreshingApplications = true
        runApplicationScan()
    }

    private func runApplicationScan() {
        // Single O(n) pass on the main actor: build a deduplicated [bundleID: appName]
        // dictionary. Everything else — file scan, NSWorkspace IPC, sorting — runs off-thread.
        let trackedApps = Dictionary(
            segments
                .filter {
                    !$0.bundleIdentifier.isEmpty
                        && !$0.bundleIdentifier.hasPrefix("productivity.")
                        && !$0.bundleIdentifier.hasPrefix("manual.")
                }
                .map { ($0.bundleIdentifier, $0.appName) },
            uniquingKeysWith: { first, _ in first }
        )

        Task {
            let applications = await Task.detached(priority: .utility) {
                var scanned = InstalledApplicationScanner.applications()
                let scannedIDs = Set(scanned.map(\.bundleIdentifier))

                // On macOS 13+, system apps like Safari live in the Cryptex sealed volume
                // and are invisible to FileManager enumeration. Resolve any tracked bundle
                // IDs the scanner missed via NSWorkspace (thread-safe, off main actor).
                for (bundleID, fallbackName) in trackedApps where !scannedIDs.contains(bundleID) {
                    let name: String
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                       let bundle = Bundle(url: url) {
                        name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                            ?? url.deletingPathExtension().lastPathComponent
                    } else {
                        name = fallbackName
                    }
                    scanned.append(InstalledApplication(name: name, bundleIdentifier: bundleID))
                }

                return scanned.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }.value

            installedApplications = applications
            isRefreshingApplications = false
        }
    }

    private func sanitizeTrackingPreferences() {
        snapshotIntervalSeconds = TrackingTuningOptions.nearestValue(
            to: TrackingPreferences.snapshotIntervalSeconds(),
            in: TrackingTuningOptions.snapshotIntervals
        )
        idleTimeoutSeconds = TrackingTuningOptions.nearestValue(
            to: TrackingPreferences.idleTimeoutSeconds(),
            in: TrackingTuningOptions.idleTimeouts
        )
        visibleCompanionWindowSeconds = TrackingTuningOptions.nearestValue(
            to: TrackingPreferences.visibleCompanionWindowSeconds(),
            in: TrackingTuningOptions.visibleCompanionWindows
        )
        timelineHorizonSeconds = TrackingTuningOptions.nearestValue(
            to: TrackingPreferences.timelineHorizonSeconds(),
            in: TrackingTuningOptions.timelineHorizons
        )
    }
}

private enum SettingsRoute: String, CaseIterable, Identifiable {
    case general
    case privacy
    case tracking
    case pomodoro
    case labeling
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .privacy: "Privacy"
        case .tracking: "Tracking"
        case .pomodoro: "Pomodoro"
        case .labeling: "Labeling"
        case .account: "Account"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Appearance and everyday app preferences"
        case .privacy: "Local-first tracking, exports, and data controls"
        case .tracking: "Personalize activity detection sensitivity"
        case .pomodoro: "Notification sounds for focus sessions and breaks"
        case .labeling: "Personal productive and unproductive app rules"
        case .account: "Local account details and account actions"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .privacy: "lock.shield"
        case .tracking: "waveform.path.ecg.rectangle"
        case .pomodoro: "timer"
        case .labeling: "tag"
        case .account: "person.crop.circle"
        }
    }
}

private enum LaunchAtLoginStatus: Equatable {
    case off
    case enabled
    case requiresApproval
    case unavailable

    static var current: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .off
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    var isToggleOn: Bool {
        switch self {
        case .enabled, .requiresApproval:
            true
        case .off, .unavailable:
            false
        }
    }

    var title: String {
        switch self {
        case .off:
            "Off"
        case .enabled:
            "Enabled"
        case .requiresApproval:
            "Needs Approval"
        case .unavailable:
            "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .off:
            "FocusGrove will stay closed after you sign in until you open it manually."
        case .enabled:
            "FocusGrove is registered with macOS and will open automatically when you sign in."
        case .requiresApproval:
            "macOS has the login item pending. Approve FocusGrove in Login Items to finish setup."
        case .unavailable:
            "Launch at Login is unavailable for this build configuration."
        }
    }

    var systemImage: String {
        switch self {
        case .off:
            "power"
        case .enabled:
            "checkmark.circle.fill"
        case .requiresApproval:
            "exclamationmark.triangle.fill"
        case .unavailable:
            "xmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .off:
            ProductivityTheme.textSecondary
        case .enabled:
            ProductivityTheme.accent
        case .requiresApproval:
            ProductivityTheme.accentSecondary
        case .unavailable:
            ProductivityTheme.accentSecondary
        }
    }
}

private struct PomodoroSoundSettingRow: View {
    let title: String
    let detail: String
    @Binding var selection: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                rowCopy
                Spacer(minLength: 12)
                soundPicker
                previewButton
            }

            VStack(alignment: .leading, spacing: 10) {
                rowCopy
                HStack(spacing: 10) {
                    soundPicker
                    previewButton
                }
            }
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.54), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.38), lineWidth: 1)
        )
    }

    private var rowCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .productivityFont(.bodyStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)
            Text(detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 220, maxWidth: 480, alignment: .leading)
    }

    private var soundPicker: some View {
        Picker(title, selection: $selection) {
            ForEach(PomodoroSoundSet.allCases) { soundSet in
                Section(soundSet.title) {
                    ForEach(soundSet.sounds) { sound in
                        Text(sound.title).tag(sound.rawValue)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 150, alignment: .trailing)
    }

    private var previewButton: some View {
        Button {
            let sound = PomodoroSound(rawValue: selection) ?? .silent
            PomodoroSoundPlayer.play(sound)
        } label: {
            Image(systemName: "play.fill")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .help("Preview \(title)")
    }
}

private enum PomodoroSoundSet: String, CaseIterable, Identifiable {
    case crystal
    case clearCue
    case utility

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crystal:
            "Crystal Set"
        case .clearCue:
            "Clear Cue Set"
        case .utility:
            "Utility"
        }
    }

    var sounds: [PomodoroSound] {
        PomodoroSound.allCases.filter { sound in
            sound.setTitle == title
        }
    }
}

private struct TrackingTuningOption: Identifiable, Hashable {
    let title: String
    let value: TimeInterval
    let isRecommended: Bool

    var id: TimeInterval { value }
}

private enum TrackingTuningOptions {
    static let idleTimeouts: [TrackingTuningOption] = [
        TrackingTuningOption(title: "3 min", value: 3 * 60, isRecommended: false),
        TrackingTuningOption(title: "5 min", value: 5 * 60, isRecommended: false),
        TrackingTuningOption(title: "10 min", value: TrackingPreferences.recommendedIdleTimeoutSeconds, isRecommended: true),
        TrackingTuningOption(title: "15 min", value: 15 * 60, isRecommended: false),
        TrackingTuningOption(title: "25 min", value: 25 * 60, isRecommended: false)
    ]

    static let visibleCompanionWindows: [TrackingTuningOption] = [
        TrackingTuningOption(title: "2 min", value: 2 * 60, isRecommended: false),
        TrackingTuningOption(title: "5 min", value: 5 * 60, isRecommended: false),
        TrackingTuningOption(title: "3 min", value: TrackingPreferences.recommendedVisibleCompanionWindowSeconds, isRecommended: true),
        TrackingTuningOption(title: "15 min", value: 15 * 60, isRecommended: false),
        TrackingTuningOption(title: "25 min", value: 25 * 60, isRecommended: false)
    ]

    static let snapshotIntervals: [TrackingTuningOption] = [
        TrackingTuningOption(title: "5 sec", value: 5, isRecommended: false),
        TrackingTuningOption(title: "10 sec", value: TrackingPreferences.recommendedSnapshotIntervalSeconds, isRecommended: true),
        TrackingTuningOption(title: "15 sec", value: 15, isRecommended: false),
        TrackingTuningOption(title: "20 sec", value: 20, isRecommended: false),
        TrackingTuningOption(title: "30 sec", value: 30, isRecommended: false)
    ]

    static let timelineHorizons: [TrackingTuningOption] = [
        TrackingTuningOption(title: "10 min", value: 10 * 60, isRecommended: false),
        TrackingTuningOption(title: "20 min", value: TrackingPreferences.recommendedTimelineHorizonSeconds, isRecommended: true),
        TrackingTuningOption(title: "30 min", value: 30 * 60, isRecommended: false),
        TrackingTuningOption(title: "45 min", value: 45 * 60, isRecommended: false),
        TrackingTuningOption(title: "60 min", value: 60 * 60, isRecommended: false)
    ]

    static func nearestValue(to value: TimeInterval, in options: [TrackingTuningOption]) -> TimeInterval {
        options.min { lhs, rhs in
            abs(lhs.value - value) < abs(rhs.value - value)
        }?.value ?? value
    }
}

private struct TrackingOptionPicker: View {
    let title: String
    let detail: String
    let options: [TrackingTuningOption]
    @Binding var selection: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                if selectedOption?.isRecommended == true {
                    Text("Recommended")
                        .productivityFont(.captionStrong)
                        .foregroundStyle(ProductivityTheme.accent)
                }
            }

            Text(detail)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(title, selection: $selection) {
                ForEach(options) { option in
                    Text(option.title + (option.isRecommended ? " *" : ""))
                        .tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
        }
    }

    private var selectedOption: TrackingTuningOption? {
        options.first { $0.value == selection }
    }
}

private struct SettingsLayoutMetrics {
    let size: CGSize
    let textScale: CGFloat
    let isFullScreen: Bool

    private var responsiveScale: CGFloat {
        min(max(size.width / 980, 1), 1.22)
    }

    private var scale: CGFloat { responsiveScale * textScale }

    var contentPadding: CGFloat {
        ProductivityTheme.contentPadding(for: size.width, isFullScreen: isFullScreen) * textScale
    }

    var contentWidth: CGFloat {
        let maximumWidth: CGFloat
        if isFullScreen {
            switch size.width {
            case ..<1380:
                maximumWidth = ProductivityTheme.contentMaxWidth
            case ..<1780:
                maximumWidth = 1600
            case ..<2200:
                maximumWidth = 1960
            default:
                maximumWidth = ProductivityTheme.fullScreenContentMaxWidth
            }
        } else {
            switch size.width {
            case ..<1380:
                maximumWidth = ProductivityTheme.contentMaxWidth
            case ..<1720:
                maximumWidth = 1520
            default:
                maximumWidth = ProductivityTheme.wideContentMaxWidth
            }
        }

        return min(max(size.width - contentPadding * 2, 0), maximumWidth)
    }

    var sectionSpacing: CGFloat { 24 * scale }
    var titleFontSize: CGFloat { 34 * scale }
    var subtitleFontSize: CGFloat { 15 * scale }
    var menuFontSize: CGFloat { 13 * scale }
    var optionFontSize: CGFloat { 14 * scale }
    var menuHorizontalPadding: CGFloat { 12 * scale }
    var menuVerticalPadding: CGFloat { 9 * scale }
    var menuMinHeight: CGFloat { 34 * scale }
    var dynamicTypeSize: DynamicTypeSize { scale > 1.12 ? .xLarge : .large }
    var controlSize: ControlSize { scale > 1.12 ? .large : .regular }
}

private struct SettingsMenuButton: View {
    let route: SettingsRoute
    let isSelected: Bool
    let metrics: SettingsLayoutMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(route.title, systemImage: route.systemImage)
                .font(ProductivityTypography.font(.controlLabel, scale: metrics.menuFontSize / 13.5, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, metrics.menuHorizontalPadding)
                .padding(.vertical, metrics.menuVerticalPadding)
                .frame(minHeight: metrics.menuMinHeight)
                .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? ProductivityTheme.textPrimary : ProductivityTheme.textSecondary)
        .contentShape(RoundedRectangle(cornerRadius: 8))
    }

    private var backgroundColor: Color {
        isSelected ? ProductivityTheme.accent.opacity(0.22) : ProductivityTheme.subtleBackground.opacity(0.58)
    }

    private var borderColor: Color {
        isSelected ? ProductivityTheme.accent.opacity(0.34) : ProductivityTheme.border.opacity(0.38)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .productivityFont(.sectionTitle)
                .foregroundStyle(ProductivityTheme.textPrimary)

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
        )
    }
}

private struct InstalledApplication: Identifiable, Hashable, Sendable {
    let name: String
    let bundleIdentifier: String

    var id: String { bundleIdentifier }

    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || bundleIdentifier.localizedCaseInsensitiveContains(query)
    }
}

private struct UnknownApplicationSummary: Identifiable, Hashable {
    let installedApplication: InstalledApplication
    let totalDuration: TimeInterval
    let occurrenceCount: Int

    var id: String { installedApplication.bundleIdentifier }
}

private struct LabelRuleSection: Identifiable {
    let rollup: ActivityLabel
    let rules: [AppLabelRule]

    var id: String { rollup.id }
}

private extension AppLabelRule {
    var displayIdentity: String {
        [
            id.uuidString,
            bundleIdentifier,
            label.id,
            label.commonRollup.id,
            String(isEnabled)
        ].joined(separator: "|")
    }
}

private enum InstalledApplicationScanner {
    nonisolated static func applications() -> [InstalledApplication] {
        let fileManager = FileManager.default
        let applicationDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        var applications: [InstalledApplication] = []
        var seenBundleIdentifiers = Set<String>()

        for directory in applicationDirectories {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                guard
                    let bundle = Bundle(url: url),
                    let bundleIdentifier = bundle.bundleIdentifier,
                    !seenBundleIdentifiers.contains(bundleIdentifier)
                else {
                    continue
                }

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                seenBundleIdentifiers.insert(bundleIdentifier)
                applications.append(InstalledApplication(name: name, bundleIdentifier: bundleIdentifier))
            }
        }

        return applications.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct LabelLibraryGroup: View {
    let rollup: ActivityLabel
    let labels: [ActivityLabel]
    let editingLabelID: String?
    let onStartEdit: (ActivityLabel) -> Void
    let onSave: (ActivityLabel, String, ActivityLabel) -> Void
    let onDelete: (ActivityLabel) -> Void
    let onCancelEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(rollup.tint)
                    .frame(width: 8, height: 8)
                Text(rollup.title)
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text("\(labels.count)")
                    .productivityFont(.note)
                    .foregroundStyle(rollup.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(rollup.tint.opacity(0.12), in: Capsule())
                Spacer(minLength: 0)
            }

            VStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.element.id) { index, label in
                    LabelLibraryRow(
                        label: label,
                        isEditing: editingLabelID == label.id,
                        onStartEdit: { onStartEdit(label) },
                        onSave: { name, newRollup in onSave(label, name, newRollup) },
                        onDelete: { onDelete(label) },
                        onCancelEdit: onCancelEdit
                    )
                    if index < labels.count - 1 {
                        Divider()
                            .padding(.leading, 54)
                            .opacity(0.4)
                    }
                }
            }
            .background(ProductivityTheme.elevatedBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.28), lineWidth: 1)
            )
        }
    }
}

private struct LabelLibraryRow: View {
    let label: ActivityLabel
    let isEditing: Bool
    let onStartEdit: () -> Void
    let onSave: (String, ActivityLabel) -> Void
    let onDelete: () -> Void
    let onCancelEdit: () -> Void

    @State private var isHovered = false
    @State private var editName: String
    @State private var editRollup: ActivityLabel

    private var isEditable: Bool {
        switch label {
        case .productive, .unproductive, .unknown: return false
        default: return true
        }
    }

    private var isDeletable: Bool {
        if case .custom = label { return true }
        return false
    }

    init(
        label: ActivityLabel,
        isEditing: Bool,
        onStartEdit: @escaping () -> Void,
        onSave: @escaping (String, ActivityLabel) -> Void,
        onDelete: @escaping () -> Void,
        onCancelEdit: @escaping () -> Void
    ) {
        self.label = label
        self.isEditing = isEditing
        self.onStartEdit = onStartEdit
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancelEdit = onCancelEdit
        _editName = State(initialValue: label.title)
        _editRollup = State(initialValue: label.commonRollup)
    }

    var body: some View {
        Group {
            if isEditing {
                editingRow
            } else {
                displayRow
            }
        }
        .animation(.smooth(duration: 0.18), value: isEditing)
    }

    private var displayRow: some View {
        HStack(spacing: 12) {
            labelGlyph(tint: label.tint)

            Text(label.title)
                .productivityFont(.bodyMedium)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            rollupChip

            if isEditable {
                HStack(spacing: 4) {
                    Button {
                        editName = label.title
                        editRollup = label.commonRollup
                        onStartEdit()
                    } label: {
                        Image(systemName: "pencil")
                            .productivityFont(.note)
                            .foregroundStyle(ProductivityTheme.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(ProductivityTheme.subtleBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)

                    if isDeletable {
                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .productivityFont(.note)
                                .foregroundStyle(Color.red.opacity(0.75))
                                .frame(width: 24, height: 24)
                                .background(ProductivityTheme.subtleBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .opacity(isHovered ? 1 : 0)
                    }
                }
            } else {
                Image(systemName: "lock.fill")
                    .productivityFont(.note)
                    .foregroundStyle(ProductivityTheme.textSecondary.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .opacity(isHovered ? 1 : 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var editingRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labelGlyph(tint: isDeletable ? ActivityLabelColor(rollup: editRollup).color : label.tint)

                if isDeletable {
                    TextField("Label name", text: $editName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                } else {
                    Text(label.title)
                        .productivityFont(.bodyMedium)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                }

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    Button("Cancel") { onCancelEdit() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(ProductivityTheme.textSecondary)

                    Button("Save") {
                        let trimmed = isDeletable ? editName.trimmingCharacters(in: .whitespacesAndNewlines) : label.title
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, editRollup)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isDeletable && editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Picker("Rollup", selection: $editRollup) {
                ForEach(ActivityLabel.commonLabels) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .padding(.leading, 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ActivityLabelColor(rollup: editRollup).color.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func labelGlyph(tint: Color) -> some View {
        Group {
            if let symbol = label.symbol {
                Text(symbol)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: label.systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 28, height: 28)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private var rollupChip: some View {
        let isBase = label.commonRollup == label
        let chipText = isBase ? "Base" : label.commonRollup.title
        return Text(chipText)
            .productivityFont(.note)
            .foregroundStyle(label.tint.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(label.tint.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(label.tint.opacity(0.2), lineWidth: 1))
    }
}

private struct LabelRuleGroupHeader: View {
    let rollup: ActivityLabel
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: rollup.systemImage)
                .font(ProductivityTypography.font(.controlIcon, scale: 0.82))
                .foregroundStyle(rollup.tint)
                .frame(width: 22, height: 22)
                .background(rollup.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))

            Text(rollup.title)
                .productivityFont(.captionStrong)
                .foregroundStyle(ProductivityTheme.textPrimary)

            Text("\(count)")
                .productivityFont(.note)
                .foregroundStyle(rollup.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(rollup.tint.opacity(0.12), in: Capsule())

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

private struct ActivityLabelGlyph: View {
    let label: ActivityLabel
    let size: CGFloat
    let iconSize: CGFloat
    var isSelected = false

    var body: some View {
        Group {
            if let symbol = label.symbol {
                Text(symbol)
                    .font(ProductivityTypography.font(.metric, scale: max(iconSize + 3, size * 0.48) / 28, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: label.systemImage)
                    .font(ProductivityTypography.font(.controlIcon, scale: iconSize / 15))
            }
        }
        .foregroundStyle(label.tint)
        .frame(width: size, height: size)
        .background(label.tint.opacity(isSelected ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(label.tint.opacity(isSelected ? 0.74 : 0.34), lineWidth: 1)
        )
    }
}

private struct CustomLabelPreviewGlyph: View {
    let symbol: String?
    let systemImage: String
    let tint: Color

    var body: some View {
        Group {
            if let symbol {
                Text(symbol)
                    .font(ProductivityTypography.font(.metric, scale: 19 / 28, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Image(systemName: systemImage)
                    .font(ProductivityTypography.font(.controlIcon))
            }
        }
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(tint.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(tint.opacity(0.74), lineWidth: 1)
        )
    }
}

private struct TrackedAppRuleRow: View {
    let rule: AppLabelRule
    var detail = "Tracked in manual mode"
    var showsRemoveButton = true
    let onLabelChange: (ActivityLabel) -> Void
    let onRemove: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                rowContent
                Spacer(minLength: 12)
                labelMenu
                if showsRemoveButton {
                    removeButton
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                rowContent
                HStack(spacing: 10) {
                    labelMenu
                    if showsRemoveButton {
                        removeButton
                    }
                }
            }
        }
        .padding(12)
        .background(ProductivityTheme.subtleBackground.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(spacing: 12) {
            ActivityLabelGlyph(label: rule.label, size: 34, iconSize: 15, isSelected: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.appName)
                    .productivityFont(.bodyStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(1)

                Text(detail)
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 220, alignment: .leading)
    }

    private var labelMenu: some View {
        Menu {
            ForEach(ActivityLabel.allCases) { label in
                Button {
                    onLabelChange(label)
                } label: {
                    Label(label.title, systemImage: rule.label == label ? "checkmark" : label.systemImage)
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(rule.label.tint)
                    .frame(width: 7, height: 7)
                Text(rule.label.title)
                    .productivityFont(.bodyMedium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(rule.label.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(rule.label.tint.opacity(0.28), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            onRemove()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .help("Remove from tracked apps")
    }

    private var borderColor: Color {
        rule.label.tint.opacity(0.28)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if DEBUG
#Preview {
    SettingsView(segments: ActivitySegment.sampleDay)
        .environment(AppEnvironment.preview())
        .frame(width: 900, height: 760)
}

#Preview("Labeling") {
    SettingsView(segments: ActivitySegment.sampleDay, initialSelection: .labeling)
        .environment(AppEnvironment.preview())
        .frame(width: 1000, height: 760)
        .preferredColorScheme(.dark)
}
#endif
