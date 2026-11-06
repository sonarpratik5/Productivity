import AppKit
import Foundation
import Observation
import SwiftUI

enum ProductivityStorage {
    static let applicationSupportDirectoryName = "Productivity"
}

enum AppPreferenceKeys {
    static let appearance = "app.appearance"
    static let isTrackingEnabled = "tracking.isEnabled"
    static let isDailyFocusHeaderEnabled = "motivation.isDailyFocusHeaderEnabled"
    static let customMotivationQuote = "motivation.customQuote"
    static let productivityThresholdPercent = "dashboard.productivityThresholdPercent"
}

enum PomodoroPreferenceKeys {
    static let focusMinutes = "pomodoro.focusMinutes"
    static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
    static let longBreakMinutes = "pomodoro.longBreakMinutes"
    static let sessionsBeforeLongBreak = "pomodoro.sessionsBeforeLongBreak"
    static let sessionHistory = "pomodoro.sessionHistory"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppTextSize: String, CaseIterable, Identifiable {
    case standard
    case large
    case extraLarge

    static let storageKey = "app.textSize"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .large: "Large"
        case .extraLarge: "Larger"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .standard: .large
        case .large: .xLarge
        case .extraLarge: .xxLarge
        }
    }

    var scaleMultiplier: CGFloat {
        switch self {
        case .standard: 1
        case .large: 1.10
        case .extraLarge: 1.20
        }
    }

    var controlSize: ControlSize {
        switch self {
        case .standard: .regular
        case .large, .extraLarge: .large
        }
    }

    var subtitle: String {
        switch self {
        case .standard: "Uses the app's default macOS sizing."
        case .large: "Adds a little more breathing room for reading and scanning."
        case .extraLarge: "Maximizes readability across dense dashboards and settings."
        }
    }

    func stepped(by offset: Int) -> AppTextSize {
        let allCases = Self.allCases
        guard let index = allCases.firstIndex(of: self) else { return self }
        let nextIndex = min(max(index + offset, allCases.startIndex), allCases.index(before: allCases.endIndex))
        return allCases[nextIndex]
    }
}

enum TrackingPreferenceKeys {
    static let snapshotIntervalSeconds = "tracking.algorithm.snapshotIntervalSeconds"
    static let idleTimeoutSeconds = "tracking.algorithm.idleTimeoutSeconds"
    static let visibleCompanionWindowSeconds = "tracking.algorithm.visibleCompanionWindowSeconds"
    static let timelineHorizonSeconds = "tracking.timeline.horizonSeconds"
    static let isTimelineEventContextOverlayEnabled = "tracking.timeline.isEventContextOverlayEnabled"
    static let isSleepHiddenInDayProgress = "tracking.timeline.isSleepHiddenInDayProgress"
}

enum TrackingPreferences {
    static let recommendedSnapshotIntervalSeconds = 10.0
    static let recommendedIdleTimeoutSeconds = 10.0 * 60.0
    static let recommendedVisibleCompanionWindowSeconds = 3.0 * 60.0
    static let recommendedTimelineHorizonSeconds = 20.0 * 60.0

    static func snapshotIntervalSeconds() -> TimeInterval {
        clampedStoredValue(
            forKey: TrackingPreferenceKeys.snapshotIntervalSeconds,
            defaultValue: recommendedSnapshotIntervalSeconds,
            range: 5...30
        )
    }

    static func idleTimeoutSeconds() -> TimeInterval {
        clampedStoredValue(
            forKey: TrackingPreferenceKeys.idleTimeoutSeconds,
            defaultValue: recommendedIdleTimeoutSeconds,
            range: (3 * 60)...(25 * 60)
        )
    }

    static func visibleCompanionWindowSeconds() -> TimeInterval {
        clampedStoredValue(
            forKey: TrackingPreferenceKeys.visibleCompanionWindowSeconds,
            defaultValue: recommendedVisibleCompanionWindowSeconds,
            range: (2 * 60)...(25 * 60)
        )
    }

    static func timelineHorizonSeconds() -> TimeInterval {
        clampedStoredValue(
            forKey: TrackingPreferenceKeys.timelineHorizonSeconds,
            defaultValue: recommendedTimelineHorizonSeconds,
            range: (10 * 60)...(60 * 60)
        )
    }

    private static func clampedStoredValue(
        forKey key: String,
        defaultValue: TimeInterval,
        range: ClosedRange<TimeInterval>
    ) -> TimeInterval {
        let value = UserDefaults.standard.double(forKey: key)
        guard value > 0 else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

enum NotificationPreferenceKeys {
    static let isPomodoroSoundEnabled = "notifications.isPomodoroSoundEnabled"
    static let pomodoroFocusStartSound = "notifications.pomodoroFocusStartSound"
    static let pomodoroShortBreakStartSound = "notifications.pomodoroShortBreakStartSound"
    static let pomodoroLongBreakStartSound = "notifications.pomodoroLongBreakStartSound"
    static let pomodoroCompletionSound = "notifications.pomodoroCompletionSound"
}

enum AccountPreferenceKeys {
    static let displayName = "account.displayName"
    static let defaultDisplayName = "Local Account"
}

enum PomodoroSound: String, CaseIterable, Identifiable, Codable {
    case prism
    case aurora
    case orbit
    case cascade
    case ignition
    case drift
    case gravity
    case signal
    case silent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prism: "Prism"
        case .aurora: "Aurora"
        case .orbit: "Orbit"
        case .cascade: "Cascade"
        case .ignition: "Ignition"
        case .drift: "Drift"
        case .gravity: "Gravity"
        case .signal: "Signal"
        case .silent: "Silent"
        }
    }

    var setTitle: String {
        switch self {
        case .prism, .aurora, .orbit, .cascade:
            "Crystal Set"
        case .ignition, .drift, .gravity, .signal:
            "Clear Cue Set"
        case .silent:
            "Utility"
        }
    }
}

enum PomodoroSoundEvent {
    case focusStart
    case shortBreakStart
    case longBreakStart
    case completion

    var preferenceKey: String {
        switch self {
        case .focusStart: NotificationPreferenceKeys.pomodoroFocusStartSound
        case .shortBreakStart: NotificationPreferenceKeys.pomodoroShortBreakStartSound
        case .longBreakStart: NotificationPreferenceKeys.pomodoroLongBreakStartSound
        case .completion: NotificationPreferenceKeys.pomodoroCompletionSound
        }
    }

    var defaultSound: PomodoroSound {
        switch self {
        case .focusStart: .prism
        case .shortBreakStart: .aurora
        case .longBreakStart: .orbit
        case .completion: .cascade
        }
    }
}

enum PomodoroSoundPlayer {
    private static var activeSounds: [NSSound] = []

    @MainActor
    static func play(_ sound: PomodoroSound) {
        guard sound != .silent,
              let data = PomodoroToneRenderer.data(for: sound),
              let nsSound = NSSound(data: data) else {
            return
        }

        nsSound.volume = 0.82
        activeSounds.append(nsSound)
        nsSound.play()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1800))
            activeSounds.removeAll { $0 === nsSound }
        }
    }

    @MainActor
    static func play(event: PomodoroSoundEvent, defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: NotificationPreferenceKeys.isPomodoroSoundEnabled) == nil
                || defaults.bool(forKey: NotificationPreferenceKeys.isPomodoroSoundEnabled) else {
            return
        }

        let rawValue = defaults.string(forKey: event.preferenceKey)
        let sound = rawValue.flatMap(PomodoroSound.init(rawValue:)) ?? event.defaultSound
        play(sound)
    }
}

private enum PomodoroToneRenderer {
    private static let sampleRate = 44_100
    private static let cachedData: [PomodoroSound: Data] = Dictionary(
        uniqueKeysWithValues: PomodoroSound.allCases.compactMap { sound in
            renderedData(for: sound).map { (sound, $0) }
        }
    )

    static func data(for sound: PomodoroSound) -> Data? {
        cachedData[sound]
    }

    private static func renderedData(for sound: PomodoroSound) -> Data? {
        let notes: [(frequency: Double, start: Double, duration: Double, volume: Double)]
        switch sound {
        case .prism:
            notes = [
                (523.25, 0.00, 0.18, 0.50),
                (659.25, 0.10, 0.20, 0.44),
                (783.99, 0.20, 0.28, 0.40),
                (1046.50, 0.38, 0.30, 0.28)
            ]
        case .aurora:
            notes = [
                (392.00, 0.00, 0.28, 0.38),
                (493.88, 0.08, 0.34, 0.34),
                (587.33, 0.18, 0.38, 0.30),
                (739.99, 0.34, 0.32, 0.24)
            ]
        case .orbit:
            notes = [
                (293.66, 0.00, 0.26, 0.42),
                (440.00, 0.06, 0.30, 0.34),
                (554.37, 0.18, 0.34, 0.30),
                (880.00, 0.40, 0.34, 0.24)
            ]
        case .cascade:
            notes = [
                (987.77, 0.00, 0.16, 0.36),
                (783.99, 0.10, 0.18, 0.34),
                (659.25, 0.20, 0.22, 0.32),
                (523.25, 0.34, 0.34, 0.30)
            ]
        case .ignition:
            notes = [
                (1046.50, 0.00, 0.08, 0.50),
                (1318.51, 0.13, 0.08, 0.46),
                (1567.98, 0.26, 0.18, 0.40)
            ]
        case .drift:
            notes = [
                (659.25, 0.00, 0.26, 0.28),
                (493.88, 0.22, 0.30, 0.30),
                (392.00, 0.48, 0.42, 0.26)
            ]
        case .gravity:
            notes = [
                (196.00, 0.00, 0.46, 0.46),
                (246.94, 0.22, 0.48, 0.36),
                (392.00, 0.62, 0.22, 0.22)
            ]
        case .signal:
            notes = [
                (783.99, 0.00, 0.10, 0.44),
                (783.99, 0.16, 0.10, 0.40),
                (1174.66, 0.34, 0.24, 0.34)
            ]
        case .silent:
            return nil
        }

        return makeWAV(notes: notes)
    }

    private static func makeWAV(notes: [(frequency: Double, start: Double, duration: Double, volume: Double)]) -> Data {
        let totalDuration = (notes.map { $0.start + $0.duration }.max() ?? 0.7) + 0.08
        let sampleCount = max(1, Int(Double(sampleRate) * totalDuration))
        var samples = Array(repeating: Double.zero, count: sampleCount)

        for note in notes {
            let startIndex = max(0, Int(note.start * Double(sampleRate)))
            let endIndex = min(sampleCount, Int((note.start + note.duration) * Double(sampleRate)))
            guard endIndex > startIndex else { continue }

            for index in startIndex..<endIndex {
                let elapsed = Double(index - startIndex) / Double(sampleRate)
                let progress = min(max(elapsed / note.duration, 0), 1)
                let attack = min(progress / 0.18, 1)
                let release = min((1 - progress) / 0.34, 1)
                let envelope = max(0, min(attack, release))
                let fundamental = sin(2 * Double.pi * note.frequency * elapsed)
                let shimmer = sin(2 * Double.pi * note.frequency * 2.01 * elapsed) * 0.18
                samples[index] += (fundamental + shimmer) * note.volume * envelope
            }
        }

        let pcmSamples = samples.map { sample -> Int16 in
            let softened = tanh(sample * 0.72)
            return Int16(max(Double(Int16.min), min(Double(Int16.max), softened * 28_000)))
        }

        return wavData(from: pcmSamples)
    }

    private static func wavData(from samples: [Int16]) -> Data {
        var data = Data()
        let byteRate = UInt32(sampleRate * 2)
        let blockAlign = UInt16(2)
        let subchunk2Size = UInt32(samples.count * 2)
        let chunkSize = UInt32(36) + subchunk2Size

        data.appendASCII("RIFF")
        data.appendLittleEndian(chunkSize)
        data.appendASCII("WAVE")
        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(UInt32(sampleRate))
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(UInt16(16))
        data.appendASCII("data")
        data.appendLittleEndian(subchunk2Size)

        for sample in samples {
            data.appendLittleEndian(UInt16(bitPattern: sample))
        }

        return data
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        append(Data(bytes: &littleEndianValue, count: MemoryLayout<UInt32>.size))
    }
}

@MainActor
@Observable
final class AppSettings {
    var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppPreferenceKeys.appearance)
            applyAppearance()
        }
    }

    init() {
        let storedAppearance = UserDefaults.standard.string(forKey: AppPreferenceKeys.appearance)
        appearance = storedAppearance.flatMap(AppAppearance.init(rawValue:)) ?? .system
        applyAppearance()
    }

    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }
}
