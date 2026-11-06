import AppKit
import Observation
import OSLog
import QuartzCore
import SwiftUI

/// Everything the menu bar button displays, derived from app state.
struct PullTimerStatusSnapshot: Equatable, Sendable {
    /// Countdown text next to the icon, or `nil` when no timer is active.
    var countdown: String?
    /// Fraction of the current timer that has elapsed (0...1).
    var progress: Double
    var isPaused: Bool
    /// SF Symbol shown when no timer is active.
    var idleSymbolName: String
    var accessibilityLabel: String
}

/// Owns FocusGrove's menu bar item and makes the icon itself the pull handle,
/// the way PullTimer does: click opens the panel, drag the icon down to set a timer.
///
/// `MenuBarExtra` can't do this — it renders its label as a static image and its
/// button runs its own tracking loop — so this uses a plain `NSStatusItem` with a
/// transparent capture view layered over the status bar button.
@MainActor
final class PullTimerStatusItemController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private let openDashboard: () -> Void
    private let statusItem: NSStatusItem
    private let overlay = PullTimerOverlayController()
    private lazy var panel = makePanel()

    private var gesture: PullTimerGesture?
    private var panelWasVisibleAtMouseDown = false
    private var lastPanelCloseTime: TimeInterval = 0
    private var lastSnapshot: PullTimerStatusSnapshot?
    private var observationTask: Task<Void, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var globalPressMonitor: Any?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "FocusGrove", category: "PullTimer")

    private static let countdownFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize,
        weight: .medium
    )

    init(
        environment: AppEnvironment,
        openDashboard: @escaping () -> Void,
        panelContent: (_ dismiss: @escaping () -> Void) -> AnyView
    ) {
        self.environment = environment
        self.openDashboard = openDashboard
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.autosaveName = "FocusGroveStatusItem"
        configureButton()
        installPanelContent(panelContent { [weak self] in self?.closePanel() })
        startObservingState()
        installGlobalPressMonitor()
        logInstallation()
    }

    private func logInstallation() {
        // Diagnostics for menu bar hosting differences across macOS releases.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, let button = self.statusItem.button else { return }
            let windowClass = button.window.map { String(describing: type(of: $0)) } ?? "nil"
            let frame = self.statusItemScreenFrame?.debugDescription ?? "nil"
            self.logger.info("Status item installed: window=\(windowClass, privacy: .public) frame=\(frame, privacy: .public) visible=\(self.statusItem.isVisible, privacy: .public)")
        }
    }

    func invalidate() {
        observationTask?.cancel()
        stopPointerPolling()
        if let globalPressMonitor {
            NSEvent.removeMonitor(globalPressMonitor)
        }
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        closePanel()
        overlay.hide()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Button

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.imageHugsTitle = true
        // Keyboard / VoiceOver "press" still toggles the panel.
        button.target = self
        button.action = #selector(statusButtonAction)
        // Fire on press, not release, so a system-hosted menu bar still lets us track the pull.
        button.sendAction(on: [.leftMouseDown])
        button.setAccessibilityIdentifier("FocusGroveMenuBarItem")
        button.setAccessibilityLabel("FocusGrove")

        let captureView = PullTimerStatusItemCaptureView(frame: button.bounds)
        captureView.autoresizingMask = [.width, .height]
        captureView.controller = self
        button.addSubview(captureView)
    }

    private var isTrackingEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKeys.isTrackingEnabled) as? Bool ?? true
    }

    private func makeSnapshot() -> PullTimerStatusSnapshot {
        let timer = environment.pomodoroViewModel
        let isActive = timer.isTimerActive

        let idleSymbolName: String
        if !isTrackingEnabled {
            idleSymbolName = "pause.circle"
        } else {
            switch environment.dashboardViewModel.trackingStatus {
            case .paused: idleSymbolName = "pause.circle"
            case .starting: idleSymbolName = "bolt.circle"
            case .tracking: idleSymbolName = "record.circle"
            case .waitingForTrackedApp: idleSymbolName = "clock"
            }
        }

        let countdown = isActive ? PullTimerDurationCalculator.menuBarCountdown(seconds: timer.remainingSeconds) : nil
        let accessibilityLabel: String
        if let countdown {
            let state = timer.isRunning ? "remaining" : "remaining, paused"
            accessibilityLabel = "FocusGrove, \(timer.phase.title), \(countdown) \(state)"
        } else {
            accessibilityLabel = "FocusGrove"
        }

        return PullTimerStatusSnapshot(
            countdown: countdown,
            progress: timer.progress,
            isPaused: isActive && !timer.isRunning,
            idleSymbolName: idleSymbolName,
            accessibilityLabel: accessibilityLabel
        )
    }

    private func startObservingState() {
        render(makeSnapshot())

        // Re-render whenever the observed timer / tracking properties change.
        observationTask = Task { [weak self] in
            let snapshots = Observations { [weak self] in
                self?.makeSnapshot()
            }
            for await snapshot in snapshots {
                guard let self else { return }
                if let snapshot { self.render(snapshot) }
            }
        }

        // The tracking toggle lives in UserDefaults (@AppStorage), which Observation can't see.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.render(self.makeSnapshot())
            }
        }
    }

    private func render(_ snapshot: PullTimerStatusSnapshot) {
        guard snapshot != lastSnapshot, let button = statusItem.button else { return }
        lastSnapshot = snapshot

        if let countdown = snapshot.countdown {
            button.image = Self.progressRingImage(progress: snapshot.progress)
            button.imagePosition = .imageLeading
            button.attributedTitle = NSAttributedString(
                string: " \(countdown)",
                attributes: [
                    .font: Self.countdownFont,
                    .foregroundColor: snapshot.isPaused ? NSColor.secondaryLabelColor : NSColor.labelColor,
                    .baselineOffset: 0.5
                ]
            )
        } else {
            let image = NSImage(systemSymbolName: snapshot.idleSymbolName, accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }
        button.setAccessibilityLabel(snapshot.accessibilityLabel)
    }

    /// Template ring whose filled wedge shows the time remaining, draining clockwise.
    static func progressRingImage(progress: Double) -> NSImage {
        let remaining = max(0, min(1, 1 - progress))
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let ringRect = rect.insetBy(dx: 1.5, dy: 1.5)
            let ring = NSBezierPath(ovalIn: ringRect)
            ring.lineWidth = 1.5
            NSColor.black.setStroke()
            ring.stroke()

            guard remaining > 0 else { return true }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let wedge = NSBezierPath()
            wedge.move(to: center)
            wedge.appendArc(
                withCenter: center,
                radius: ringRect.width / 2 - 2.25,
                startAngle: 90,
                endAngle: 90 - 360 * remaining,
                clockwise: true
            )
            wedge.close()
            NSColor.black.setFill()
            wedge.fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Pull gesture
    //
    // Press delivery differs by macOS release. On older systems the status item is an
    // in-process window and the capture view gets real mouse events. On newer systems the
    // menu bar is hosted by the system, so the app may only hear about a press through the
    // button's action or as a global event. All three paths funnel into `beginPress`, and
    // presses that don't come with an in-process event stream are tracked by polling the
    // pointer every display frame — which works no matter who receives the drag events.

    /// Where a press was first detected, for dedupe and diagnostics.
    enum PressSource: String {
        case captureView
        case buttonAction
        case globalMonitor
    }

    /// Snapshot of the physical pointer, injectable so tests can drive the polling path.
    struct PointerState {
        var location: CGPoint
        var isLeftButtonDown: Bool
        var isShiftDown: Bool
    }

    var pointerProvider: () -> PointerState = {
        PointerState(
            location: NSEvent.mouseLocation,
            isLeftButtonDown: NSEvent.pressedMouseButtons & 1 != 0,
            isShiftDown: NSEvent.modifierFlags.contains(.shift)
        )
    }

    private var pressSource: PressSource?
    private var pointerDisplayLink: CADisplayLink?
    /// When the last press ended, used to swallow the trailing "click" a system-hosted
    /// menu bar may send after a pull was already handled.
    private var lastPressEndTime: TimeInterval = -1

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    fileprivate func mouseDown(_ event: NSEvent) {
        beginPress(at: Self.screenLocation(of: event), source: .captureView)
    }

    fileprivate func mouseDragged(_ event: NSEvent) {
        guard pressSource == .captureView else { return }
        updatePress(to: Self.screenLocation(of: event), fineMode: event.modifierFlags.contains(.shift))
    }

    fileprivate func mouseUp(_ event: NSEvent) {
        guard pressSource == .captureView else { return }
        updatePress(to: Self.screenLocation(of: event), fineMode: event.modifierFlags.contains(.shift))
        finishPress()
    }

    /// Button action (sent on mouse-down) — also what VoiceOver / keyboard "press" triggers.
    @objc private func statusButtonAction() {
        handleExternalPress(source: .buttonAction)
    }

    /// Entry point for presses that arrive without an in-process event stream.
    func handleExternalPress(source: PressSource) {
        guard gesture == nil else { return }
        // A system-hosted menu bar can report the same physical press twice (global
        // mouse-down, then the button action); ignore the echo of a press just handled.
        guard now - lastPressEndTime > 0.35 else {
            logger.debug("Ignored \(source.rawValue, privacy: .public) echo of a finished press")
            return
        }

        let pointer = pointerProvider()
        guard pointer.isLeftButtonDown else {
            // No button held: a synthetic press (VoiceOver, keyboard) or a late click.
            logger.debug("\(source.rawValue, privacy: .public) press without a held button: toggling panel")
            lastPressEndTime = now
            if panel.isVisible {
                closePanel()
            } else if now - lastPanelCloseTime > 0.35 {
                // Don't reopen a panel this same press just closed via the outside-click monitor.
                showPanel()
            }
            return
        }

        beginPress(at: pointer.location, source: source)
        startPointerPolling()
    }

    private func beginPress(at location: CGPoint, source: PressSource) {
        guard gesture == nil else { return }
        logger.debug("Press began via \(source.rawValue, privacy: .public) at \(location.debugDescription, privacy: .public)")
        panelWasVisibleAtMouseDown = panel.isVisible
            // The panel may already have closed itself (resign-key / outside click) for this same press.
            || now - lastPanelCloseTime < 0.35
        closePanel()
        statusItem.button?.highlight(true)
        pressSource = source
        gesture = PullTimerGesture(origin: location)
    }

    private func updatePress(to location: CGPoint, fineMode: Bool) {
        guard var gesture else { return }
        guard location != gesture.current || fineMode != gesture.isFineMode else { return }
        let wasDetached = gesture.isHandleDetached
        let minutesChanged = gesture.update(to: location, fineMode: fineMode)
        self.gesture = gesture

        if gesture.isHandleDetached && !wasDetached {
            logger.debug("Handle detached; pull started")
            beginPull(at: gesture.current)
        }
        guard gesture.isHandleDetached else { return }

        overlay.update(
            handle: gesture.current,
            minutes: gesture.minutes,
            isFineMode: gesture.isFineMode,
            isCancelling: gesture.phase == .cancelling
        )

        if minutesChanged && (gesture.isFineMode || PullTimerGesture.isDetent(gesture.minutes)) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func finishPress() {
        guard let gesture else { return }
        self.gesture = nil
        pressSource = nil
        lastPressEndTime = now
        stopPointerPolling()
        endPull()

        let outcome = gesture.end()
        logger.debug("Press finished: \(String(describing: outcome), privacy: .public)")
        switch outcome {
        case .click:
            if panelWasVisibleAtMouseDown {
                statusItem.button?.highlight(false)
            } else {
                showPanel()
            }
        case .start(let minutes):
            statusItem.button?.highlight(false)
            environment.pomodoroViewModel.setFocusDuration(minutes, resetTimer: true, startImmediately: true)
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            overlay.snapBack()
        case .cancel:
            statusItem.button?.highlight(false)
            overlay.snapBack()
        }
    }

    // MARK: Pointer polling

    private func startPointerPolling() {
        stopPointerPolling()
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        guard let link = screen?.displayLink(target: self, selector: #selector(pollPointer)) else { return }
        // Common modes keep it firing during menu/event tracking loops.
        link.add(to: .main, forMode: .common)
        pointerDisplayLink = link
    }

    private func stopPointerPolling() {
        pointerDisplayLink?.invalidate()
        pointerDisplayLink = nil
    }

    /// One frame of pointer tracking for externally delivered presses.
    @objc func pollPointer() {
        guard gesture != nil, pressSource != .captureView else {
            stopPointerPolling()
            return
        }
        let pointer = pointerProvider()
        updatePress(to: pointer.location, fineMode: pointer.isShiftDown)
        if !pointer.isLeftButtonDown {
            finishPress()
        }
    }

    // MARK: Global press detection

    /// Screen frame of the icon, used to recognise presses the system delivers globally.
    var statusItemScreenFrame: CGRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func installGlobalPressMonitor() {
        // Only mouse-downs are observed, and only acted on inside our own icon.
        globalPressMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let frame = self.statusItemScreenFrame else { return }
                let location = NSEvent.mouseLocation
                // Menu bar items are hit along the full bar height; allow a little slack.
                guard frame.insetBy(dx: -1, dy: -4).contains(location) else { return }
                self.handleExternalPress(source: .globalMonitor)
            }
        }
    }

    /// Pointer position for this event in screen coordinates. Reading it from the event
    /// (rather than `NSEvent.mouseLocation`) keeps the handle in sync with the event stream.
    private static func screenLocation(of event: NSEvent) -> CGPoint {
        guard let window = event.window else { return NSEvent.mouseLocation }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func beginPull(at point: CGPoint) {
        guard let anchor = iconAnchorPoint() else { return }
        overlay.begin(anchor: anchor, handle: point)
        // The icon "leaves" the menu bar while its handle is being pulled.
        statusItem.button?.animator().alphaValue = 0.35

        // Esc aborts the pull (only delivered while FocusGrove is the active app).
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.gesture != nil else { return event }
            self.cancelPull()
            return nil
        }
    }

    private func endPull() {
        statusItem.button?.animator().alphaValue = 1
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    private func cancelPull() {
        gesture = nil
        pressSource = nil
        lastPressEndTime = now
        stopPointerPolling()
        endPull()
        statusItem.button?.highlight(false)
        overlay.snapBack()
    }

    /// Center of the status item's icon in screen coordinates: where the cord is tied.
    private func iconAnchorPoint() -> CGPoint? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        // With a countdown showing, tie the cord to the ring icon rather than the whole button.
        let target = button.image == nil ? button.bounds : button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        let frame = window.convertToScreen(button.convert(target, to: nil))
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: - Context menu

    fileprivate func showContextMenu() {
        guard let button = statusItem.button else { return }
        closePanel()
        let timer = environment.pomodoroViewModel
        let menu = NSMenu()

        menu.addItem(menuItem("Open Dashboard", symbol: "arrow.up.forward.app") { [weak self] in
            self?.openDashboard()
        })
        menu.addItem(.separator())

        if timer.isTimerActive {
            menu.addItem(menuItem(timer.isRunning ? "Pause Timer" : "Resume Timer",
                                  symbol: timer.isRunning ? "pause.fill" : "play.fill") {
                timer.toggleRunning()
            })
            menu.addItem(menuItem("Stop Timer", symbol: "stop.fill") {
                timer.reset()
            })
        }

        let quickStart = NSMenu()
        for minutes in PomodoroViewModel.presetFocusDurations {
            quickStart.addItem(menuItem(PullTimerDurationCalculator.formattedDuration(minutes: minutes), symbol: nil) {
                timer.setFocusDuration(minutes, resetTimer: true, startImmediately: true)
            })
        }
        let quickStartItem = NSMenuItem(title: "Start Focus Timer", action: nil, keyEquivalent: "")
        quickStartItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        quickStartItem.submenu = quickStart
        menu.addItem(quickStartItem)

        let hint = NSMenuItem(title: "Tip: pull the icon down to set a timer", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)

        menu.addItem(.separator())
        menu.addItem(menuItem("Quit FocusGrove", symbol: "power") {
            NSApplication.shared.terminate(nil)
        })

        let origin = NSPoint(x: 0, y: button.isFlipped ? button.bounds.maxY + 5 : -5)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    private func menuItem(_ title: String, symbol: String?, action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    // MARK: - Panel

    private func makePanel() -> PullTimerStatusPanel {
        let panel = PullTimerStatusPanel()
        panel.delegate = self
        return panel
    }

    private func installPanelContent(_ content: AnyView) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel.setHostedView(hostingView)
    }

    private func showPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
        let size = panel.fittingContentSize()

        var origin = CGPoint(x: buttonFrame.midX - size.width / 2, y: buttonFrame.minY - 6 - size.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }

        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        button.highlight(true)

        // Clicks in other apps don't always resign our key panel; close on any outside click.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }
    }

    private func closePanel() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if panel.isVisible {
            lastPanelCloseTime = ProcessInfo.processInfo.systemUptime
            panel.orderOut(nil)
        }
        if gesture == nil {
            statusItem.button?.highlight(false)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        closePanel()
    }

    // MARK: - Test hooks

    var statusButton: NSStatusBarButton? { statusItem.button }
    var isPanelVisible: Bool { panel.isVisible }
}

// MARK: - Supporting AppKit types

/// Transparent view laid over the status bar button that receives the raw mouse
/// events, so pulling the icon itself (not panel content) drives the timer.
private final class PullTimerStatusItemCaptureView: NSView {
    weak var controller: PullTimerStatusItemController?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        // Control-click behaves like right-click, as everywhere else on macOS.
        if event.modifierFlags.contains(.control) {
            controller?.showContextMenu()
        } else {
            controller?.mouseDown(event)
        }
    }
    override func mouseDragged(with event: NSEvent) { controller?.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { controller?.mouseUp(event) }
    override func rightMouseDown(with event: NSEvent) { controller?.showContextMenu() }
}

/// Borderless, non-activating panel shown when the icon is clicked. Non-activating
/// means opening it never drags the dashboard window in front of other apps.
private final class PullTimerStatusPanel: NSPanel {
    private let effectView = NSVisualEffectView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .utilityWindow

        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        contentView = effectView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func setHostedView(_ view: NSView) {
        effectView.subviews.forEach { $0.removeFromSuperview() }
        view.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            view.topAnchor.constraint(equalTo: effectView.topAnchor),
            view.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }

    func fittingContentSize() -> CGSize {
        effectView.subviews.first?.fittingSize ?? CGSize(width: 360, height: 480)
    }

    override func cancelOperation(_ sender: Any?) {
        // Esc closes the panel; resigning key lets the controller clean up.
        orderOut(nil)
    }
}

/// `NSMenuItem` that runs a closure, avoiding a selector per menu command.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(performHandler), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func performHandler() {
        handler()
    }
}
