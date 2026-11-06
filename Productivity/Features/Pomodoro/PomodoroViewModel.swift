import AppKit
import Foundation
import Observation

struct PomodoroConfiguration: Codable, Equatable, Sendable {
    nonisolated static let focusMinutesRange = 1...180
    nonisolated static let shortBreakMinutesRange = 1...30
    nonisolated static let longBreakMinutesRange = 5...60
    nonisolated static let sessionsBeforeLongBreakRange = 2...8

    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsBeforeLongBreak: Int

    enum CodingKeys: String, CodingKey {
        case focusMinutes
        case shortBreakMinutes
        case longBreakMinutes
        case sessionsBeforeLongBreak
    }

    nonisolated init(
        focusMinutes: Int,
        shortBreakMinutes: Int,
        longBreakMinutes: Int,
        sessionsBeforeLongBreak: Int
    ) {
        self.focusMinutes = Self.clamped(focusMinutes, to: Self.focusMinutesRange)
        self.shortBreakMinutes = Self.clamped(shortBreakMinutes, to: Self.shortBreakMinutesRange)
        self.longBreakMinutes = Self.clamped(longBreakMinutes, to: Self.longBreakMinutesRange)
        self.sessionsBeforeLongBreak = Self.clamped(sessionsBeforeLongBreak, to: Self.sessionsBeforeLongBreakRange)
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            focusMinutes: try container.decode(Int.self, forKey: .focusMinutes),
            shortBreakMinutes: try container.decode(Int.self, forKey: .shortBreakMinutes),
            longBreakMinutes: try container.decode(Int.self, forKey: .longBreakMinutes),
            sessionsBeforeLongBreak: try container.decode(Int.self, forKey: .sessionsBeforeLongBreak)
        )
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focusMinutes, forKey: .focusMinutes)
        try container.encode(shortBreakMinutes, forKey: .shortBreakMinutes)
        try container.encode(longBreakMinutes, forKey: .longBreakMinutes)
        try container.encode(sessionsBeforeLongBreak, forKey: .sessionsBeforeLongBreak)
    }

    static func storedDefaults() -> PomodoroConfiguration {
        PomodoroConfiguration(
            focusMinutes: storedValue(forKey: PomodoroPreferenceKeys.focusMinutes, fallback: 25),
            shortBreakMinutes: storedValue(forKey: PomodoroPreferenceKeys.shortBreakMinutes, fallback: 5),
            longBreakMinutes: storedValue(forKey: PomodoroPreferenceKeys.longBreakMinutes, fallback: 15),
            sessionsBeforeLongBreak: storedValue(forKey: PomodoroPreferenceKeys.sessionsBeforeLongBreak, fallback: 4)
        )
    }

    private static func storedValue(forKey key: String, fallback: Int) -> Int {
        let value = UserDefaults.standard.integer(forKey: key)
        return value == 0 ? fallback : value
    }

    nonisolated var normalized: PomodoroConfiguration {
        PomodoroConfiguration(
            focusMinutes: focusMinutes,
            shortBreakMinutes: shortBreakMinutes,
            longBreakMinutes: longBreakMinutes,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak
        )
    }

    nonisolated private static func clamped(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

enum PomodoroPhase: String, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short Break"
        case .longBreak: "Long Break"
        }
    }

    var systemImage: String {
        switch self {
        case .focus: "timer"
        case .shortBreak: "cup.and.saucer"
        case .longBreak: "sparkles"
        }
    }
}

struct PomodoroSessionRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let completedAt: Date
    let focusMinutes: Int

    init(id: UUID = UUID(), completedAt: Date, focusMinutes: Int) {
        self.id = id
        self.completedAt = completedAt
        self.focusMinutes = focusMinutes
    }
}

@MainActor
@Observable
final class PomodoroViewModel {
    static let presetFocusDurations: [Int] = [10, 15, 25, 45, 60]

    var configuration: PomodoroConfiguration {
        didSet {
            let normalizedConfiguration = configuration.normalized
            guard configuration == normalizedConfiguration else {
                configuration = normalizedConfiguration
                return
            }
            persistConfiguration()
            guard !isRunning else { return }
            remainingSeconds = duration(for: phase)
        }
    }

    var phase: PomodoroPhase = .focus
    var remainingSeconds: TimeInterval
    var sessionHistory: [PomodoroSessionRecord] {
        didSet {
            persistSessionHistory()
        }
    }
    var isRunning = false

    @ObservationIgnored private var timerTask: Task<Void, Never>?

    init(configuration: PomodoroConfiguration? = nil) {
        let resolvedConfiguration = configuration ?? PomodoroConfiguration.storedDefaults()
        self.configuration = resolvedConfiguration
        self.sessionHistory = Self.loadSessionHistory()
        remainingSeconds = TimeInterval(resolvedConfiguration.focusMinutes * 60)
    }

    var completedFocusSessions: Int {
        let calendar = Calendar.current
        let today = Date()
        return sessionHistory.filter { calendar.isDate($0.completedAt, inSameDayAs: today) }.count
    }

    var totalFocusMinutesToday: Int {
        let calendar = Calendar.current
        let today = Date()
        return sessionHistory
            .filter { calendar.isDate($0.completedAt, inSameDayAs: today) }
            .reduce(0) { $0 + $1.focusMinutes }
    }

    var recentSessionHistory: [PomodoroSessionRecord] {
        Array(sessionHistory.prefix(20))
    }

    var totalSeconds: TimeInterval {
        duration(for: phase)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, min(1, 1 - (remainingSeconds / totalSeconds)))
    }

    var formattedRemainingTime: String {
        let totalSeconds = max(0, Int(remainingSeconds))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var isTimerActive: Bool {
        isRunning || (remainingSeconds < totalSeconds && remainingSeconds > 0)
    }

    func toggleRunning() {
        isRunning ? pause() : start()
    }

    func reset() {
        pause()
        remainingSeconds = duration(for: phase)
    }

    func skip() {
        advancePhase(playsSound: false, countsCompletion: false, shouldContinueRunning: isRunning)
    }

    func selectPhase(_ phase: PomodoroPhase) {
        pause()
        self.phase = phase
        remainingSeconds = duration(for: phase)
    }

    func setFocusDuration(_ minutes: Int, resetTimer: Bool = true, startImmediately: Bool = false) {
        let clamped = min(max(minutes, PomodoroConfiguration.focusMinutesRange.lowerBound), PomodoroConfiguration.focusMinutesRange.upperBound)
        phase = .focus
        configuration.focusMinutes = clamped
        if resetTimer || !isRunning {
            pause()
            remainingSeconds = TimeInterval(clamped * 60)
        }
        if startImmediately {
            start()
        }
    }

    func setShortBreakDuration(_ minutes: Int, resetTimer: Bool = true, startImmediately: Bool = false) {
        let clamped = min(max(minutes, PomodoroConfiguration.shortBreakMinutesRange.lowerBound), PomodoroConfiguration.shortBreakMinutesRange.upperBound)
        phase = .shortBreak
        configuration.shortBreakMinutes = clamped
        if resetTimer || !isRunning {
            pause()
            remainingSeconds = TimeInterval(clamped * 60)
        }
        if startImmediately {
            start()
        }
    }

    func setLongBreakDuration(_ minutes: Int, resetTimer: Bool = true, startImmediately: Bool = false) {
        let clamped = min(max(minutes, PomodoroConfiguration.longBreakMinutesRange.lowerBound), PomodoroConfiguration.longBreakMinutesRange.upperBound)
        phase = .longBreak
        configuration.longBreakMinutes = clamped
        if resetTimer || !isRunning {
            pause()
            remainingSeconds = TimeInterval(clamped * 60)
        }
        if startImmediately {
            start()
        }
    }

    func adjustRemainingTime(by minutes: Int) {
        let delta = TimeInterval(minutes * 60)
        let newRemaining = remainingSeconds + delta
        remainingSeconds = max(10, min(newRemaining, TimeInterval(PomodoroConfiguration.focusMinutesRange.upperBound * 60)))
    }

    func clearHistory() {
        sessionHistory.removeAll()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startTimerTask()
    }

    func pause() {
        isRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    private func advancePhase(
        playsSound: Bool,
        countsCompletion: Bool,
        shouldContinueRunning: Bool
    ) {
        let previousPhase = phase
        let previousFocusMinutes = configuration.focusMinutes

        if countsCompletion && previousPhase == .focus {
            let record = PomodoroSessionRecord(
                completedAt: Date(),
                focusMinutes: previousFocusMinutes
            )
            sessionHistory.insert(record, at: 0)
        }

        switch previousPhase {
        case .focus:
            let completedToday = completedFocusSessions
            if completedToday > 0 && completedToday % configuration.sessionsBeforeLongBreak == 0 {
                phase = .longBreak
            } else {
                phase = .shortBreak
            }
        case .shortBreak, .longBreak:
            phase = .focus
        }

        remainingSeconds = duration(for: phase)

        if playsSound {
            NSSound.beep()
        }

        if shouldContinueRunning {
            start()
        } else {
            pause()
        }
    }

    private func duration(for phase: PomodoroPhase) -> TimeInterval {
        switch phase {
        case .focus:
            TimeInterval(configuration.focusMinutes * 60)
        case .shortBreak:
            TimeInterval(configuration.shortBreakMinutes * 60)
        case .longBreak:
            TimeInterval(configuration.longBreakMinutes * 60)
        }
    }

    private func startTimerTask() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }

                if self.remainingSeconds > 1 {
                    self.remainingSeconds -= 1
                } else {
                    self.remainingSeconds = 0
                    self.advancePhase(
                        playsSound: true,
                        countsCompletion: true,
                        shouldContinueRunning: false
                    )
                    return
                }
            }
        }
    }

    private func persistConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set(configuration.focusMinutes, forKey: PomodoroPreferenceKeys.focusMinutes)
        defaults.set(configuration.shortBreakMinutes, forKey: PomodoroPreferenceKeys.shortBreakMinutes)
        defaults.set(configuration.longBreakMinutes, forKey: PomodoroPreferenceKeys.longBreakMinutes)
        defaults.set(configuration.sessionsBeforeLongBreak, forKey: PomodoroPreferenceKeys.sessionsBeforeLongBreak)
    }

    private func persistSessionHistory() {
        guard let data = try? JSONEncoder().encode(sessionHistory) else { return }
        UserDefaults.standard.set(data, forKey: PomodoroPreferenceKeys.sessionHistory)
    }

    private static func loadSessionHistory() -> [PomodoroSessionRecord] {
        guard let data = UserDefaults.standard.data(forKey: PomodoroPreferenceKeys.sessionHistory),
              let history = try? JSONDecoder().decode([PomodoroSessionRecord].self, from: data) else {
            return []
        }
        return history.sorted { $0.completedAt > $1.completedAt }
    }
}
