import Testing
@testable import Productivity
import AppKit
import CoreGraphics
import SwiftUI

// MARK: - Pull gesture state machine

@MainActor
@Suite("PullTimerGesture: pulling the menu bar icon")
struct PullTimerGestureStateTests {
    /// Screen coordinates are y-up, so a pull of `distance` points lowers y.
    private let origin = CGPoint(x: 800, y: 1100)

    private func pulled(_ distance: CGFloat, dx: CGFloat = 0) -> CGPoint {
        CGPoint(x: origin.x + dx, y: origin.y - distance)
    }

    @Test("press and release without moving is a click")
    func stationaryPressIsClick() {
        let gesture = PullTimerGesture(origin: origin)
        #expect(gesture.phase == .pressed)
        #expect(!gesture.isHandleDetached)
        #expect(gesture.end() == .click)
    }

    @Test("a tiny wiggle within click slop still counts as a click")
    func wiggleWithinSlopIsClick() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: CGPoint(x: origin.x + 2, y: origin.y - 2), fineMode: false)
        #expect(gesture.phase == .pressed)
        #expect(gesture.end() == .click)
    }

    @Test("dragging sideways along the menu bar neither opens the panel nor starts a timer")
    func sidewaysDragCancels() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: CGPoint(x: origin.x + 60, y: origin.y - 3), fineMode: false)
        #expect(gesture.phase == .pressed)
        #expect(gesture.end() == .cancel)
    }

    @Test("dragging upward never detaches the handle")
    func upwardDragStaysPressed() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: CGPoint(x: origin.x, y: origin.y + 40), fineMode: false)
        #expect(gesture.pullDistance == 0)
        #expect(!gesture.isHandleDetached)
    }

    @Test("pulling past the threshold detaches the handle and selects minutes")
    func pullingDetachesHandle() {
        var gesture = PullTimerGesture(origin: origin)
        let changed = gesture.update(to: pulled(PullTimerDurationCalculator.minimumDragThreshold), fineMode: false)
        #expect(changed)
        #expect(gesture.phase == .pulling)
        #expect(gesture.isHandleDetached)
        #expect(gesture.minutes == 1)
    }

    @Test("minutes track the duration curve and release starts that timer", arguments: [20.0, 60.0, 172.0, 250.0, 400.0, 700.0])
    func releaseStartsSelectedDuration(distance: Double) {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: pulled(CGFloat(distance), dx: 25), fineMode: false)
        let expected = PullTimerDurationCalculator.calculateDuration(dragDistanceY: CGFloat(distance))
        #expect(gesture.minutes == expected)
        #expect(gesture.end() == .start(minutes: expected))
    }

    @Test("dragging back into the menu bar cancels, and pulling out again resumes")
    func dragBackCancelsThenResumes() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: pulled(172), fineMode: false)
        #expect(gesture.minutes == 25)

        gesture.update(to: pulled(4), fineMode: false)
        #expect(gesture.phase == .cancelling)
        #expect(gesture.minutes == 0)
        #expect(gesture.isHandleDetached, "handle stays visible so the user sees the cancel state")
        #expect(gesture.end() == .cancel)

        gesture.update(to: pulled(172), fineMode: false)
        #expect(gesture.phase == .pulling)
        #expect(gesture.end() == .start(minutes: 25))
    }

    @Test("update reports whether the minute value changed")
    func updateReportsChanges() {
        var gesture = PullTimerGesture(origin: origin)
        let firstChange = gesture.update(to: pulled(172), fineMode: false)
        let secondChange = gesture.update(to: pulled(172.5), fineMode: false)
        #expect(firstChange)
        #expect(!secondChange)
    }

    @Test("holding Shift anchors precision mode without jumping the readout")
    func fineModeIsAnchored() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: pulled(172), fineMode: false)
        let coarse = gesture.minutes

        gesture.update(to: pulled(172), fineMode: true)
        #expect(gesture.isFineMode)
        #expect(gesture.minutes == coarse)

        let step = PullTimerGesture.fineModePointsPerMinute
        gesture.update(to: pulled(172 + step), fineMode: true)
        #expect(gesture.minutes == coarse + 1)

        gesture.update(to: pulled(172 + step * 10), fineMode: true)
        #expect(gesture.minutes == coarse + 10)

        gesture.update(to: pulled(172 - step * 3), fineMode: true)
        #expect(gesture.minutes == coarse - 3)
    }

    @Test("releasing Shift returns to the coarse curve")
    func releasingShiftReturnsToCoarse() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: pulled(172), fineMode: true)
        gesture.update(to: pulled(172 + 60), fineMode: true)
        gesture.update(to: pulled(232), fineMode: false)
        #expect(!gesture.isFineMode)
        #expect(gesture.minutes == PullTimerDurationCalculator.calculateDuration(dragDistanceY: 232))
    }

    @Test("precision mode is clamped to 1...180 minutes")
    func fineModeClamps() {
        var gesture = PullTimerGesture(origin: origin)
        gesture.update(to: pulled(600), fineMode: true)
        gesture.update(to: pulled(2000), fineMode: true)
        #expect(gesture.minutes == PullTimerDurationCalculator.maximumMinutes)

        var shortGesture = PullTimerGesture(origin: origin)
        shortGesture.update(to: pulled(100), fineMode: true)
        shortGesture.update(to: pulled(13), fineMode: true)
        #expect(shortGesture.minutes == 1)
    }

    @Test("haptic detents land on 5-minute marks only")
    func detents() {
        #expect(PullTimerGesture.isDetent(5))
        #expect(PullTimerGesture.isDetent(25))
        #expect(PullTimerGesture.isDetent(180))
        #expect(!PullTimerGesture.isDetent(0))
        #expect(!PullTimerGesture.isDetent(7))
    }
}

// MARK: - Menu bar countdown

@MainActor
@Suite("Menu bar countdown and duration curve")
struct PullTimerMenuBarCountdownTests {
    @Test("countdown text is compact and correct", arguments: [
        (0.0, "0:00"),
        (-5.0, "0:00"),
        (9.0, "0:09"),
        (59.0, "0:59"),
        (59.4, "1:00"),
        (300.0, "5:00"),
        (1499.0, "24:59"),
        (3600.0, "1:00:00"),
        (3723.0, "1:02:03"),
        (10800.0, "3:00:00")
    ])
    func countdownFormatting(seconds: Double, expected: String) {
        #expect(PullTimerDurationCalculator.menuBarCountdown(seconds: seconds) == expected)
    }

    @Test("pulling further never selects a shorter duration")
    func durationCurveIsMonotonic() {
        var previous = 0
        for tenth in 0...7000 {
            let minutes = PullTimerDurationCalculator.calculateDuration(dragDistanceY: CGFloat(tenth) / 10)
            #expect(minutes >= previous, "drop at \(CGFloat(tenth) / 10)pt")
            previous = minutes
        }
        #expect(previous == PullTimerDurationCalculator.maximumMinutes)
    }

    @Test("progress ring is a 16pt template image at every progress value", arguments: [0.0, 0.25, 0.5, 1.0, 1.5])
    func progressRingImage(progress: Double) {
        let image = PullTimerStatusItemController.progressRingImage(progress: progress)
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 16, height: 16))
        #expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }
}

// MARK: - End-to-end: real status item, real mouse events

/// Drives a real `NSStatusItem` by sending mouse events through its window, so the
/// events travel the same hit-test → capture view → controller path as a user's pull.
@MainActor
@Suite("Status item pull-to-set integration", .serialized)
struct PullTimerStatusItemIntegrationTests {
    @MainActor
    private struct Harness {
        let controller: PullTimerStatusItemController
        let environment: AppEnvironment
        let button: NSStatusBarButton
        let window: NSWindow
        let savedFocusMinutes: Any?

        var timer: PomodoroViewModel { environment.pomodoroViewModel }

        /// Center of the icon in its window's coordinates.
        var iconCenter: NSPoint {
            button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        }

        func send(_ type: NSEvent.EventType, pulledDown distance: CGFloat = 0, shift: Bool = false) {
            let location = NSPoint(x: iconCenter.x + distance * 0.1, y: iconCenter.y - distance)
            let event = NSEvent.mouseEvent(
                with: type,
                location: location,
                modifierFlags: shift ? [.shift] : [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            )
            if let event { window.sendEvent(event) }
        }

        /// Presses the icon, drags through each distance in turn, then releases.
        func pull(through distances: [CGFloat], shift: Bool = false) {
            send(.leftMouseDown)
            for distance in distances {
                send(.leftMouseDragged, pulledDown: distance, shift: shift)
            }
            send(.leftMouseUp, pulledDown: distances.last ?? 0, shift: shift)
        }

        func tearDown() {
            timer.pause()
            controller.invalidate()
            // setFocusDuration persists the length; restore the user's real preference.
            if let savedFocusMinutes {
                UserDefaults.standard.set(savedFocusMinutes, forKey: PomodoroPreferenceKeys.focusMinutes)
            } else {
                UserDefaults.standard.removeObject(forKey: PomodoroPreferenceKeys.focusMinutes)
            }
        }
    }

    private func makeHarness() async throws -> Harness {
        let savedFocusMinutes = UserDefaults.standard.object(forKey: PomodoroPreferenceKeys.focusMinutes)
        let environment = AppEnvironment.preview()
        environment.pomodoroViewModel.pause()
        environment.pomodoroViewModel.selectPhase(.focus)
        let controller = PullTimerStatusItemController(
            environment: environment,
            openDashboard: {},
            panelContent: { _ in AnyView(Text("Panel").frame(width: 200, height: 120)) }
        )
        let button = try #require(controller.statusButton)
        let window = try #require(button.window, "status item button should live in a status bar window")

        // A new status item is laid out on a later run-loop pass; until then the icon's
        // window geometry is stale and hit-testing misses it. Wait until a click at the
        // icon's center would land on the capture view, exactly as a real click does.
        var isHitTestable = false
        for _ in 0..<100 {
            window.layoutIfNeeded()
            let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            if let contentView = window.contentView,
               let hit = contentView.hitTest(contentView.superview?.convert(center, from: nil) ?? center),
               hit !== button, hit.isDescendant(of: button) {
                isHitTestable = true
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(isHitTestable, "mouse events at the icon must reach the pull capture view")

        return Harness(
            controller: controller,
            environment: environment,
            button: button,
            window: window,
            savedFocusMinutes: savedFocusMinutes
        )
    }

    private func waitForTitle(of button: NSStatusBarButton, containing text: String) async -> Bool {
        for _ in 0..<100 {
            if button.attributedTitle.string.contains(text) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test("pulling the icon down 172pt starts a 25 minute focus timer and shows the countdown")
    func pullStartsTimerAndShowsCountdown() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        #expect(harness.button.attributedTitle.string.isEmpty, "idle icon shows no countdown")

        harness.pull(through: [6, 20, 60, 120, 172])

        #expect(harness.timer.isRunning)
        #expect(harness.timer.phase == .focus)
        #expect(harness.timer.remainingSeconds == 25 * 60)
        #expect(!harness.controller.isPanelVisible, "a pull must not open the panel")
        #expect(await waitForTitle(of: harness.button, containing: "25:00") || harness.button.attributedTitle.string.contains("24:5"))
        #expect(harness.button.imagePosition == .imageLeading)
    }

    @Test("a short pull sets a short timer")
    func shortPull() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }

        harness.pull(through: [8, 16])

        #expect(harness.timer.isRunning)
        #expect(harness.timer.remainingSeconds == 60)
    }

    @Test("holding Shift while pulling gives minute precision")
    func shiftPrecisionPull() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }

        harness.send(.leftMouseDown)
        harness.send(.leftMouseDragged, pulledDown: 172)
        harness.send(.leftMouseDragged, pulledDown: 172, shift: true)
        harness.send(.leftMouseDragged, pulledDown: 172 + PullTimerGesture.fineModePointsPerMinute * 7, shift: true)
        harness.send(.leftMouseUp, pulledDown: 172 + PullTimerGesture.fineModePointsPerMinute * 7, shift: true)

        #expect(harness.timer.isRunning)
        #expect(harness.timer.remainingSeconds == 32 * 60)
    }

    @Test("dragging the handle back into the menu bar cancels without touching the timer")
    func dragBackCancels() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        let before = harness.timer.remainingSeconds

        harness.pull(through: [40, 172, 60, 3])

        #expect(!harness.timer.isRunning)
        #expect(harness.timer.remainingSeconds == before)
        #expect(!harness.controller.isPanelVisible)
    }

    @Test("clicking the icon toggles the panel instead of starting a timer")
    func clickTogglesPanel() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }

        harness.pull(through: [])
        #expect(harness.controller.isPanelVisible)
        #expect(!harness.timer.isRunning)

        harness.pull(through: [])
        #expect(!harness.controller.isPanelVisible)
    }

    @Test("pulling while the panel is open closes it and still sets the timer")
    func pullWhilePanelOpen() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }

        harness.pull(through: [])
        #expect(harness.controller.isPanelVisible)

        harness.pull(through: [30, 100, 172])
        #expect(!harness.controller.isPanelVisible)
        #expect(harness.timer.remainingSeconds == 25 * 60)
        #expect(harness.timer.isRunning)
    }

    /// Mutable fake pointer for driving the display-link polling path.
    @MainActor
    private final class FakePointer {
        var state: PullTimerStatusItemController.PointerState

        init(at location: CGPoint) {
            state = .init(location: location, isLeftButtonDown: false, isShiftDown: false)
        }
    }

    private func iconScreenCenter(_ harness: Harness) throws -> CGPoint {
        let frame = try #require(harness.controller.statusItemScreenFrame)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test("a press reported by the system (button action / global monitor) is tracked by polling", arguments: [
        PullTimerStatusItemController.PressSource.buttonAction,
        .globalMonitor
    ])
    func externalPressPollsPointer(source: PullTimerStatusItemController.PressSource) async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        let center = try iconScreenCenter(harness)
        let pointer = FakePointer(at: center)
        harness.controller.pointerProvider = { pointer.state }

        pointer.state.isLeftButtonDown = true
        harness.controller.handleExternalPress(source: source)
        for distance in [10.0, 60.0, 120.0, 172.0] {
            pointer.state.location = CGPoint(x: center.x + 8, y: center.y - distance)
            harness.controller.pollPointer()
        }
        #expect(!harness.timer.isRunning, "nothing starts until the button is released")

        pointer.state.isLeftButtonDown = false
        harness.controller.pollPointer()

        #expect(harness.timer.isRunning)
        #expect(harness.timer.remainingSeconds == 25 * 60)
        #expect(!harness.controller.isPanelVisible)
    }

    @Test("the trailing click a system menu bar sends after a pull does not open the panel")
    func echoAfterPullIsIgnored() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        let center = try iconScreenCenter(harness)
        let pointer = FakePointer(at: center)
        harness.controller.pointerProvider = { pointer.state }

        pointer.state.isLeftButtonDown = true
        harness.controller.handleExternalPress(source: .globalMonitor)
        pointer.state.location = CGPoint(x: center.x, y: center.y - 172)
        harness.controller.pollPointer()
        pointer.state.isLeftButtonDown = false
        harness.controller.pollPointer()
        #expect(harness.timer.isRunning)

        // Echo of the same physical press, e.g. the button action on release.
        harness.controller.handleExternalPress(source: .buttonAction)
        #expect(!harness.controller.isPanelVisible)
    }

    @Test("a stationary press-and-release reported by the system opens the panel")
    func externalClickOpensPanel() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        let pointer = FakePointer(at: try iconScreenCenter(harness))
        harness.controller.pointerProvider = { pointer.state }

        pointer.state.isLeftButtonDown = true
        harness.controller.handleExternalPress(source: .globalMonitor)
        harness.controller.pollPointer()
        pointer.state.isLeftButtonDown = false
        harness.controller.pollPointer()

        #expect(harness.controller.isPanelVisible)
        #expect(!harness.timer.isRunning)
    }

    @Test("VoiceOver / keyboard press (no button held) toggles the panel")
    func accessibilityPressTogglesPanel() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }
        let pointer = FakePointer(at: try iconScreenCenter(harness))
        harness.controller.pointerProvider = { pointer.state }

        harness.controller.handleExternalPress(source: .buttonAction)
        #expect(harness.controller.isPanelVisible)
    }

    @Test("pausing keeps the countdown visible; resetting removes it")
    func countdownFollowsTimerState() async throws {
        let harness = try await makeHarness()
        defer { harness.tearDown() }

        harness.timer.setFocusDuration(10, resetTimer: true, startImmediately: true)
        #expect(await waitForTitle(of: harness.button, containing: "10:00") || harness.button.attributedTitle.string.contains("9:5"))

        harness.timer.pause()
        harness.timer.remainingSeconds = 5 * 60
        #expect(await waitForTitle(of: harness.button, containing: "5:00"))
        #expect(harness.button.accessibilityLabel()?.contains("paused") == true)

        harness.timer.reset()
        for _ in 0..<100 where !harness.button.attributedTitle.string.isEmpty {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(harness.button.attributedTitle.string.isEmpty)
        #expect(harness.button.imagePosition == .imageOnly)
        #expect(harness.button.accessibilityLabel() == "FocusGrove")
    }
}
