import AppKit
import SwiftUI
import UserNotifications

@main
struct ProductivityApp: App {
    @NSApplicationDelegateAdaptor(ProductivityAppDelegate.self) private var appDelegate
    @AppStorage(AppPreferenceKeys.appearance) private var appearance = AppAppearance.system
    @AppStorage(AppTextSize.storageKey) private var textSize = AppTextSize.standard
    @AppStorage(ProductivityTheme.storageKey) private var theme = AppTheme.amethyst
    @AppStorage(AppPreferenceKeys.isTrackingEnabled) private var isTrackingEnabled = true
    @AppStorage("dashboard.selection") private var dashboardSelection: DashboardRoute = .today
    @State private var environment: AppEnvironment

    init() {
        let environment = AppEnvironment()
        _environment = State(initialValue: environment)

        // Previews and unit-test hosts never get a menu bar item; UI tests do, since they drive it.
        guard !Self.isRunningInXcodePreview, !Self.isRunningUnderXCTest else { return }
        // Defer until NSApp has finished launching before touching the status bar.
        DispatchQueue.main.async {
            ProductivityAppRuntime.shared.installStatusItem(environment: environment)
        }
    }

    var body: some Scene {
        WindowGroup("FocusGrove", id: "main") {
            Group {
                if Self.isRunningInXcodePreview {
                    Color.clear
                        .frame(width: 1, height: 1)
                } else {
                    ContentView()
                        .background(DashboardWindowAccessor())
                        .background(DashboardOpenWindowBridge())
                }
            }
            .environment(environment)
            .environment(\.productivityTextScale, textSize.scaleMultiplier)
            .preferredColorScheme(appearance.colorScheme)
            .dynamicTypeSize(textSize.dynamicTypeSize)
            .controlSize(textSize.controlSize)
            .tint(ProductivityTheme.accent)
            .id("\(theme.rawValue)-\(textSize.rawValue)")
            .task(id: appearance) {
                guard !Self.shouldSuppressRuntimeWork else { return }
                ProductivityAppRuntime.shared.environment = environment
                environment.appSettings.appearance = appearance
            }
            .task(id: isTrackingEnabled) {
                guard !Self.shouldSuppressRuntimeWork else { return }
                ProductivityAppRuntime.shared.environment = environment
                await environment.reconcileTracking(isEnabled: isTrackingEnabled)
            }
            .task(id: isTrackingEnabled) {
                guard !Self.shouldSuppressRuntimeWork else { return }
                await environment.dashboardViewModel.loadPersistedSegmentsIfNeeded()
                // Hand off to the AppEnvironment-owned task so the writer survives window hide.
                environment.startWidgetSync(isTrackingEnabled: isTrackingEnabled)
            }
            .onOpenURL { url in
                if let route = DashboardRoute(widgetURL: url) {
                    dashboardSelection = route
                }
            }
        }
        .defaultSize(width: 1220, height: 820)
        .defaultLaunchBehavior(Self.shouldSuppressDashboardOnLaunch ? .suppressed : .presented)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        // The menu bar item is an AppKit NSStatusItem (see PullTimerStatusItemController)
        // so the icon itself can be pulled down to set a timer.
    }

    private static var isRunningInXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.isRunningUnderXCTest
    }

    private static var isRunningForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-ProductivityUITests")
            || ProcessInfo.processInfo.environment["PRODUCTIVITY_UI_TESTS"] == "1"
    }

    private static var shouldSuppressDashboardOnLaunch: Bool {
        isRunningInXcodePreview
    }

    private static var shouldSuppressRuntimeWork: Bool {
        isRunningInXcodePreview || isRunningUnderXCTest || isRunningForUITests
    }
}

final class ProductivityAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var isFinishingTermination = false
    private var hasRepliedToTermination = false
    private var terminationCleanupTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !isFinishingTermination else { return false }
        ProductivityWindowPresenter.openOrPresentDashboardWindow()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !ProcessInfo.processInfo.isRunningUnderXCTest else {
            return .terminateNow
        }

        guard !isFinishingTermination else { return .terminateNow }
        isFinishingTermination = true

        terminationCleanupTask = Task { @MainActor [weak self, weak sender] in
            await ProductivityAppRuntime.shared.environment?.prepareForTermination()
            self?.replyToTermination(sender)
        }

        // Use a background-thread timer so the timeout fires even if the main actor is momentarily
        // busy (e.g., waiting for an ioQueue operation to complete).
        let capturedSelf = self
        let capturedSender = sender
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) {
            DispatchQueue.main.async {
                capturedSelf.terminationCleanupTask?.cancel()
                capturedSelf.replyToTermination(capturedSender)
            }
        }

        return .terminateLater
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    @MainActor
    private func replyToTermination(_ sender: NSApplication?) {
        guard !hasRepliedToTermination else { return }
        hasRepliedToTermination = true
        terminationCleanupTask?.cancel()
        terminationCleanupTask = nil
        (sender ?? NSApplication.shared).reply(toApplicationShouldTerminate: true)
    }
}

private extension ProcessInfo {
    var isRunningUnderXCTest: Bool {
        environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || environment["XCTestBundlePath"] != nil
    }
}

@MainActor
private final class ProductivityAppRuntime {
    static let shared = ProductivityAppRuntime()
    weak var environment: AppEnvironment?
    var openDashboardWindow: (() -> Void)?
    private var statusItemController: PullTimerStatusItemController?

    private init() {}

    func installStatusItem(environment: AppEnvironment) {
        guard statusItemController == nil else { return }
        self.environment = environment
        statusItemController = PullTimerStatusItemController(
            environment: environment,
            openDashboard: { ProductivityWindowPresenter.openOrPresentDashboardWindow() },
            panelContent: { dismiss in
                AnyView(MenuBarPanelContent(environment: environment, dismiss: dismiss))
            }
        )
    }
}

/// Root of the status item panel: supplies the app-wide preferences that the
/// SwiftUI scenes normally inject, since the panel lives outside any scene.
private struct MenuBarPanelContent: View {
    let environment: AppEnvironment
    let dismiss: () -> Void
    @AppStorage(AppPreferenceKeys.appearance) private var appearance = AppAppearance.system
    @AppStorage(AppTextSize.storageKey) private var textSize = AppTextSize.standard
    @AppStorage(AppPreferenceKeys.isTrackingEnabled) private var isTrackingEnabled = true

    var body: some View {
        ProductivityMenuBarView(
            environment: environment,
            isTrackingEnabled: $isTrackingEnabled,
            dismiss: dismiss
        )
        .environment(environment)
        .tint(ProductivityTheme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .environment(\.productivityTextScale, textSize.scaleMultiplier)
    }
}

private enum ProductivityWindowPresenter {
    private static var registeredDashboardWindow: NSWindow?
    private static var shouldPresentRegisteredWindow = false
    private static let dashboardWindowIdentifier = NSUserInterfaceItemIdentifier("FocusGroveDashboardWindow")

    static func activateApplication() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func registerDashboardWindow(_ window: NSWindow) {
        registeredDashboardWindow = window
        window.identifier = dashboardWindowIdentifier
        window.title = "FocusGrove"
        window.isReleasedWhenClosed = false

        if shouldPresentRegisteredWindow {
            shouldPresentRegisteredWindow = false
            show(window)
        }
    }

    @discardableResult
    static func presentDashboardWindow() -> Bool {
        activateApplication()

        if let window = dashboardWindow() {
            show(window)
            return true
        }

        Task { @MainActor in
            for _ in 0..<6 {
                guard let window = dashboardWindow() else {
                    try? await Task.sleep(for: .milliseconds(120))
                    continue
                }

                show(window)
                return
            }
        }

        shouldPresentRegisteredWindow = true
        return false
    }

    static func openOrPresentDashboardWindow() {
        if presentDashboardWindow() {
            return
        }

        ProductivityAppRuntime.shared.openDashboardWindow?()
        activateApplication()

        Task { @MainActor in
            for _ in 0..<10 {
                guard let window = dashboardWindow() else {
                    try? await Task.sleep(for: .milliseconds(80))
                    continue
                }

                shouldPresentRegisteredWindow = false
                show(window)
                return
            }
        }
    }

    private static func dashboardWindow() -> NSWindow? {
        if let registeredDashboardWindow {
            return registeredDashboardWindow
        }

        return NSApp.windows.first { window in
            (window.identifier == dashboardWindowIdentifier || window.title == "FocusGrove")
                && !window.isExcludedFromWindowsMenu
                && !(window is NSPanel)
        }
    }

    private static func show(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

private struct DashboardWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.attach(to: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        private let maximumRegistrationAttempts = 20
        private weak var view: NSView?
        private var registrationAttempts = 0
        // Previous delegate is forwarded so SwiftUI's own delegate hooks still work.
        private weak var previousDelegate: AnyObject?

        func attach(to view: NSView) {
            if self.view !== view {
                registrationAttempts = 0
            }
            self.view = view
            DispatchQueue.main.async { [weak self] in
                self?.registerWindowIfPossible()
            }
        }

        private func registerWindowIfPossible() {
            guard let view else { return }
            guard let window = view.window else {
                guard registrationAttempts < maximumRegistrationAttempts else { return }
                registrationAttempts += 1
                DispatchQueue.main.async { [weak self] in
                    self?.registerWindowIfPossible()
                }
                return
            }

            if window.delegate !== self {
                previousDelegate = window.delegate as AnyObject?
                window.delegate = self
            }
            ProductivityWindowPresenter.registerDashboardWindow(window)
        }

        // Hide the window instead of closing it so the app stays alive as a menu-bar accessory.
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.orderOut(nil)
            return false
        }

        // Forward all other delegate calls to whatever delegate was previously set (e.g., SwiftUI's).
        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let prev = previousDelegate as? NSWindowDelegate, (prev as AnyObject).responds(to: aSelector) {
                return prev
            }
            return super.forwardingTarget(for: aSelector)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return (previousDelegate as? NSWindowDelegate).map { ($0 as AnyObject).responds(to: aSelector) } == true
        }
    }
}

private struct DashboardOpenWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                ProductivityAppRuntime.shared.openDashboardWindow = {
                    openWindow(id: "main")
                }
            }
    }
}

private struct ProductivityMenuBarView: View {
    let environment: AppEnvironment
    @Binding var isTrackingEnabled: Bool
    var dismiss: () -> Void = {}

    private var viewModel: DashboardViewModel {
        environment.dashboardViewModel
    }

    private var pomodoroViewModel: PomodoroViewModel {
        environment.pomodoroViewModel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            metricsGrid
            pomodoroPanel
            trackingControl

            Divider()

            Button {
                dismiss()
                ProductivityWindowPresenter.openOrPresentDashboardWindow()
            } label: {
                Label("Open Dashboard", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("MenuBarOpenDashboardButton")

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit FocusGrove", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("MenuBarQuitButton")
        }
        .padding(18)
        .frame(width: 360)
        .accessibilityIdentifier("MenuBarPopover")
        .background(Color.clear)
        .containerBackground(
            ProductivityTheme.background.opacity(0.82),
            for: .window
        )
        .task {
            await viewModel.loadPersistedSegmentsIfNeeded()
        }
        .onChange(of: isTrackingEnabled) { _, isEnabled in
            Task {
                await environment.reconcileTracking(isEnabled: isEnabled)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text("FocusGrove")
                    .productivityFont(.sectionTitle)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text("\(productivityPercentage)% productive today")
                    .productivityFont(.caption)
                    .foregroundStyle(ProductivityTheme.textSecondary)
            }

            Spacer()

            statusBadge
        }
    }

    private var trackingControl: some View {
        HStack(spacing: 12) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tracking")
                        .productivityFont(.bodyMedium)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text(statusTitle)
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
            } icon: {
                Image(systemName: statusSystemImage)
                    .foregroundStyle(statusColor)
                    .frame(width: 20)
            }

            Spacer()

            Toggle("Tracking", isOn: $isTrackingEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityIdentifier("MenuBarTrackingToggle")
        }
        .padding(12)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.38), lineWidth: 1)
        )
    }

    private var metricsGrid: some View {
        HStack(spacing: 10) {
            metricTile(
                title: "Now",
                value: currentActivityTitle,
                systemImage: "dot.radiowaves.left.and.right",
                tint: statusColor
            )
            metricTile(
                title: "Tracked",
                value: DurationFormatting.abbreviated(viewModel.overview.totalTrackedTime),
                systemImage: "timer",
                tint: ProductivityTheme.accent
            )
            metricTile(
                title: "Focus",
                value: "\(pomodoroViewModel.completedFocusSessions)",
                systemImage: "checkmark.circle",
                tint: ProductivityTheme.accentSecondary
            )
        }
    }

    private func metricTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .productivityFont(.noteMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Text(value)
                .font(ProductivityTypography.font(.sectionTitle))
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(ProductivityTheme.elevatedBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.34), lineWidth: 1)
        )
    }

    private var pomodoroPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(ProductivityTheme.border.opacity(0.55), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: pomodoroViewModel.progress)
                        .stroke(
                            ProductivityTheme.accent,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Image(systemName: pomodoroViewModel.phase.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ProductivityTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pomodoroViewModel.phase.title)
                        .productivityFont(.bodyMedium)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                    Text(pomodoroViewModel.isRunning ? "Pomodoro running" : "Pomodoro ready")
                        .productivityFont(.caption)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Spacer()

                Text(pomodoroViewModel.formattedRemainingTime)
                    .font(ProductivityTypography.font(.metricMonospaced))
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .contentTransition(.numericText())
            }

            progressBar
            pomodoroControls

            Picker("Phase", selection: Binding(
                get: { pomodoroViewModel.phase },
                set: { pomodoroViewModel.selectPhase($0) }
            )) {
                ForEach(PomodoroPhase.allCases) { phase in
                    Text(phase.title).tag(phase)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("MenuBarPhasePicker")
        }
        .padding(14)
        .background(ProductivityTheme.subtleBackground.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.38), lineWidth: 1)
        )
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(ProductivityTheme.border.opacity(0.34))
                RoundedRectangle(cornerRadius: 4)
                    .fill(ProductivityTheme.accent.gradient)
                    .frame(width: proxy.size.width * pomodoroViewModel.progress)
            }
        }
        .frame(height: 8)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .animation(.smooth(duration: 0.28), value: pomodoroViewModel.progress)
    }

    private var pomodoroControls: some View {
        HStack(spacing: 10) {
            Button {
                pomodoroViewModel.toggleRunning()
            } label: {
                Label(
                    pomodoroViewModel.isRunning ? "Pause" : "Start",
                    systemImage: pomodoroViewModel.isRunning ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("MenuBarPomodoroStartPauseButton")

            Button {
                pomodoroViewModel.reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 28)
            }
            .help("Reset Pomodoro")
            .accessibilityIdentifier("MenuBarPomodoroResetButton")

            Button {
                pomodoroViewModel.skip()
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 28)
            }
            .help("Skip Phase")
            .accessibilityIdentifier("MenuBarPomodoroSkipButton")
        }
        .controlSize(.large)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(statusBadgeTitle)
                .productivityFont(.captionMedium)
                .foregroundStyle(ProductivityTheme.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ProductivityTheme.subtleBackground, in: Capsule())
        .overlay(
            Capsule()
                .stroke(ProductivityTheme.border.opacity(0.36), lineWidth: 1)
        )
    }

    private var productivityPercentage: Int {
        guard viewModel.overview.totalTrackedTime > 0 else { return 0 }
        return Int(viewModel.overview.productivityRatio * 100)
    }

    private var productivityTint: Color {
        switch productivityPercentage {
        case 70...:
            ActivityLabel.productive.tint
        case 35..<70:
            ProductivityTheme.accentSecondary
        default:
            ActivityLabel.unproductive.tint
        }
    }

    private var currentActivityTitle: String {
        guard isTrackingEnabled else { return "Paused" }

        switch viewModel.trackingStatus {
        case .paused:
            return "Paused"
        case .starting:
            return "Starting"
        case .waitingForTrackedApp:
            return "Waiting"
        case .tracking:
            return environment.activityTracker.currentSegments
                .filter { !$0.isLifecycleContext && !$0.isSleepEvent }
                .max { $0.endDate < $1.endDate }?
                .appName ?? "Active"
        }
    }

    private var statusTitle: String {
        guard isTrackingEnabled else { return "Tracking paused" }

        return switch viewModel.trackingStatus {
        case .paused:
            "Tracking paused"
        case .starting:
            "Starting tracker"
        case .tracking:
            "Tracking active"
        case .waitingForTrackedApp:
            "Waiting for active app"
        }
    }

    private var statusBadgeTitle: String {
        guard isTrackingEnabled else { return "Paused" }

        return switch viewModel.trackingStatus {
        case .paused:
            "Paused"
        case .starting:
            "Starting"
        case .tracking:
            "Tracking"
        case .waitingForTrackedApp:
            "Waiting"
        }
    }

    private var statusColor: Color {
        guard isTrackingEnabled else { return ProductivityTheme.textSecondary }

        return switch viewModel.trackingStatus {
        case .paused:
            ProductivityTheme.textSecondary
        case .starting:
            ProductivityTheme.accentSecondary
        case .tracking:
            ProductivityTheme.accent
        case .waitingForTrackedApp:
            ProductivityTheme.accentSecondary
        }
    }

    private var statusSystemImage: String {
        guard isTrackingEnabled else { return "pause.circle.fill" }

        return switch viewModel.trackingStatus {
        case .paused:
            "pause.circle.fill"
        case .starting:
            "bolt.circle.fill"
        case .tracking:
            "record.circle.fill"
        case .waitingForTrackedApp:
            "clock.fill"
        }
    }
}
