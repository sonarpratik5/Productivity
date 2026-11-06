import Foundation

struct ActivityLabelDefinition: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var title: String
    var systemImage: String
    var symbol: String?
    var red: Double
    var green: Double
    var blue: Double
    var rollup: ActivityLabel

    init(id: String, title: String, systemImage: String, symbol: String? = nil, tint: ActivityLabelColor, rollup: ActivityLabel) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.symbol = symbol
        self.red = tint.red
        self.green = tint.green
        self.blue = tint.blue
        self.rollup = rollup
    }

    nonisolated static func == (lhs: ActivityLabelDefinition, rhs: ActivityLabelDefinition) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.systemImage == rhs.systemImage
            && lhs.symbol == rhs.symbol
            && lhs.red == rhs.red
            && lhs.green == rhs.green
            && lhs.blue == rhs.blue
            && lhs.rollup.id == rhs.rollup.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(systemImage)
        hasher.combine(symbol)
        hasher.combine(red)
        hasher.combine(green)
        hasher.combine(blue)
        hasher.combine(rollup.id)
    }

    var label: ActivityLabel { ActivityLabel(id: id) }
}

struct ActivityLabelColor: Hashable, Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    static let productive = ActivityLabelColor(red: 0.18, green: 0.68, blue: 0.50)
    static let unproductive = ActivityLabelColor(red: 1.00, green: 0.55, blue: 0.35)
    static let unknown = ActivityLabelColor(red: 0.60, green: 0.63, blue: 0.64)
    static let sleep = ActivityLabelColor(red: 0.38, green: 0.35, blue: 0.68)

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(rollup: ActivityLabel) {
        switch rollup.commonRollup {
        case .productive:
            self = .productive
        case .unproductive:
            self = .unproductive
        case .unknown:
            self = .unknown
        default:
            self = .unknown
        }
    }
}

enum ActivityLabel: Identifiable, Hashable, Codable, Sendable {
    case productive
    case unproductive
    case unknown
    case hobby
    case vacation
    case sleep
    case focus
    case health
    case custom(String)

    nonisolated var id: String {
        switch self {
        case .productive: "productive"
        case .unproductive: "unproductive"
        case .unknown: "unknown"
        case .hobby: "hobby"
        case .vacation: "vacation"
        case .sleep: "sleep"
        case .focus: "focus"
        case .health: "health"
        case .custom(let id): id
        }
    }

    nonisolated static func == (lhs: ActivityLabel, rhs: ActivityLabel) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(id: String) {
        let id = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            self = .unknown
            return
        }

        switch id {
        case Self.productive.id:
            self = .productive
        case Self.unproductive.id:
            self = .unproductive
        case Self.unknown.id:
            self = .unknown
        case Self.hobby.id:
            self = .hobby
        case Self.vacation.id:
            self = .vacation
        case Self.sleep.id:
            self = .sleep
        case Self.focus.id:
            self = .focus
        case Self.health.id:
            self = .health
        default:
            self = .custom(id)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(id: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }

    var title: String { definition.title }
    var systemImage: String { definition.systemImage }
    var symbol: String? { definition.symbol }
    var commonRollup: ActivityLabel {
        if case .custom = self {
            return ActivityLabelCatalog.commonRollup(for: definition.rollup)
        }
        if let override = ActivityLabelCatalog.builtinRollupOverride(for: id) {
            return override
        }
        return ActivityLabelCatalog.commonRollup(for: definition.rollup)
    }
    var category: ActivityCategory {
        switch self {
        case .productive, .focus, .hobby, .health:
            .focus
        case .unproductive, .vacation:
            .entertainment
        case .sleep:
            .system
        case .unknown:
            .unknown
        case .custom:
            commonRollup.categoryForRollup
        }
    }
    var productivityScore: Double { commonRollup.productivityScoreForRollup }

    static var commonLabels: [ActivityLabel] { [.productive, .unproductive, .unknown] }
    static var predefinedSpecificLabels: [ActivityLabel] { [.hobby, .vacation, .sleep, .focus, .health] }
    static var allCases: [ActivityLabel] { ActivityLabelCatalog.availableLabels() }

    static func from(category: ActivityCategory) -> ActivityLabel {
        switch category {
        case .focus:
            .focus
        case .communication, .research:
            .productive
        case .entertainment, .system:
            .unproductive
        case .unknown:
            .unknown
        }
    }

    static func rollupDuration(for rollup: ActivityLabel, in items: [(label: ActivityLabel, duration: TimeInterval)]) -> TimeInterval {
        items
            .filter { $0.label.commonRollup == rollup.commonRollup }
            .reduce(0) { result, item in
                guard item.duration.isFinite, item.duration > 0 else { return result }
                return result + item.duration
            }
    }

    private var definition: ActivityLabelDefinition {
        ActivityLabelCatalog.definition(for: self)
    }

    private var categoryForRollup: ActivityCategory {
        switch self {
        case .productive:
            .focus
        case .unproductive:
            .entertainment
        case .unknown:
            .unknown
        default:
            commonRollup.categoryForRollup
        }
    }

    private var productivityScoreForRollup: Double {
        switch self {
        case .productive:
            0.9
        case .unproductive:
            0.05
        case .unknown:
            0.2
        default:
            commonRollup.productivityScoreForRollup
        }
    }
}

enum ActivityLabelCatalog {
    static let customLabelIDPrefix = "custom."
    private static let customLabelsKey = "activity.customLabels"
    private static let revisionKey = "activity.labelsRevision"
    private static let builtinRollupOverridesKey = "activity.builtinRollupOverrides"

    static let predefinedDefinitions: [ActivityLabelDefinition] = [
        ActivityLabelDefinition(id: ActivityLabel.productive.id, title: "Productive", systemImage: "checkmark.circle.fill", tint: .productive, rollup: .productive),
        ActivityLabelDefinition(id: ActivityLabel.unproductive.id, title: "Unproductive", systemImage: "minus.circle.fill", tint: .unproductive, rollup: .unproductive),
        ActivityLabelDefinition(id: ActivityLabel.unknown.id, title: "Unknown", systemImage: "questionmark.circle.fill", tint: .unknown, rollup: .unknown),
        ActivityLabelDefinition(id: ActivityLabel.hobby.id, title: "Hobby", systemImage: "paintpalette.fill", tint: .productive, rollup: .productive),
        ActivityLabelDefinition(id: ActivityLabel.vacation.id, title: "Vacation", systemImage: "sun.max.fill", tint: .unproductive, rollup: .unproductive),
        ActivityLabelDefinition(id: ActivityLabel.sleep.id, title: "Sleep", systemImage: "moon.zzz.fill", tint: .sleep, rollup: .unknown),
        ActivityLabelDefinition(id: ActivityLabel.focus.id, title: "Focus", systemImage: "scope", tint: .productive, rollup: .productive),
        ActivityLabelDefinition(id: ActivityLabel.health.id, title: "Health", systemImage: "heart.fill", tint: .productive, rollup: .productive)
    ]

    static func availableLabels() -> [ActivityLabel] {
        predefinedDefinitions.map(\.label) + customDefinitions().map(\.label)
    }

    static func customDefinitions(defaults: UserDefaults = .standard) -> [ActivityLabelDefinition] {
        guard let data = defaults.data(forKey: customLabelsKey),
              let definitions = try? JSONDecoder().decode([ActivityLabelDefinition].self, from: data) else {
            return []
        }

        return definitions.filter { $0.id.hasPrefix(customLabelIDPrefix) && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func commonRollup(for label: ActivityLabel) -> ActivityLabel {
        switch label {
        case .productive, .focus, .hobby, .health:
            .productive
        case .unproductive, .vacation:
            .unproductive
        case .sleep, .unknown, .custom:
            .unknown
        }
    }

    static func definition(for label: ActivityLabel) -> ActivityLabelDefinition {
        if let definition = predefinedDefinitions.first(where: { $0.id == label.id }) {
            return definition
        }

        if let definition = customDefinitions().first(where: { $0.id == label.id }) {
            return definition
        }

        return ActivityLabelDefinition(id: label.id, title: "Custom", systemImage: "tag.fill", tint: ActivityLabelColor(red: 0.70, green: 0.46, blue: 1.00), rollup: .unknown)
    }

    static func addCustomLabel(title: String, systemImage: String, symbol: String? = nil, tint: ActivityLabelColor, rollup: ActivityLabel, defaults: UserDefaults = .standard) -> ActivityLabel {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = ActivityLabel.custom("\(customLabelIDPrefix)\(UUID().uuidString)")
        let definition = ActivityLabelDefinition(
            id: label.id,
            title: trimmedTitle.isEmpty ? "Custom label" : trimmedTitle,
            systemImage: systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tag.fill" : systemImage,
            symbol: normalizedSymbol(symbol),
            tint: tint,
            rollup: rollup.commonRollup
        )
        var definitions = customDefinitions(defaults: defaults)
        definitions.append(definition)
        saveCustomDefinitions(definitions, defaults: defaults)
        return label
    }

    private static func normalizedSymbol(_ symbol: String?) -> String? {
        let trimmedSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedSymbol.first.map(String.init)
    }

    static func saveCustomDefinitions(_ definitions: [ActivityLabelDefinition], defaults: UserDefaults = .standard) {
        let uniqueDefinitions = definitions.reduce(into: [ActivityLabelDefinition]()) { result, definition in
            let title = definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard definition.id.hasPrefix(customLabelIDPrefix), !title.isEmpty, !result.contains(where: { $0.id == definition.id }) else { return }
            result.append(ActivityLabelDefinition(
                id: definition.id,
                title: title,
                systemImage: definition.systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "tag.fill" : definition.systemImage,
                symbol: normalizedSymbol(definition.symbol),
                tint: ActivityLabelColor(red: clampedColorComponent(definition.red), green: clampedColorComponent(definition.green), blue: clampedColorComponent(definition.blue)),
                rollup: commonRollup(for: definition.rollup)
            ))
        }

        if let data = try? JSONEncoder().encode(uniqueDefinitions) {
            defaults.set(data, forKey: customLabelsKey)
            defaults.set(UUID().uuidString, forKey: revisionKey)
        }
    }

    private static func clampedColorComponent(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    static func clearCustomDefinitions(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: customLabelsKey)
        defaults.set(UUID().uuidString, forKey: revisionKey)
    }

    static func builtinRollupOverride(for labelID: String, defaults: UserDefaults = .standard) -> ActivityLabel? {
        guard let data = defaults.data(forKey: builtinRollupOverridesKey),
              let dict = try? JSONDecoder().decode([String: ActivityLabel].self, from: data) else {
            return nil
        }
        return dict[labelID]
    }

    static func saveBuiltinRollupOverride(for labelID: String, rollup: ActivityLabel, defaults: UserDefaults = .standard) {
        var overrides: [String: ActivityLabel]
        if let data = defaults.data(forKey: builtinRollupOverridesKey),
           let existing = try? JSONDecoder().decode([String: ActivityLabel].self, from: data) {
            overrides = existing
        } else {
            overrides = [:]
        }
        overrides[labelID] = commonRollup(for: rollup)
        if let data = try? JSONEncoder().encode(overrides) {
            defaults.set(data, forKey: builtinRollupOverridesKey)
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
