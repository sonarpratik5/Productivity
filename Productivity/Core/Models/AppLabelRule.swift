import Foundation

enum AppTrackingMode: String, CaseIterable, Identifiable {
    case all
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All Apps"
        case .manual: "Manual"
        }
    }
}

struct AppLabelRule: Identifiable, Codable, Hashable {
    let id: UUID
    var appName: String
    var bundleIdentifier: String
    var label: ActivityLabel
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleIdentifier: String,
        label: ActivityLabel,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.label = label
        self.isEnabled = isEnabled
    }
}

enum AppLabelRuleStore {
    static let storageKey = "label.rules"
    static let manualStorageKey = "label.manualTrackingRules"
    static let trackingModeKey = "tracking.appSelectionMode"
    static let revisionKey = "label.rulesRevision"

    static let defaultRules: [AppLabelRule] = [
        AppLabelRule(appName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", label: .focus),
        AppLabelRule(appName: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", label: .focus),
        AppLabelRule(appName: "Terminal", bundleIdentifier: "com.apple.Terminal", label: .focus),
        AppLabelRule(appName: "iTerm", bundleIdentifier: "com.googlecode.iterm2", label: .focus),
        AppLabelRule(appName: "Notes", bundleIdentifier: "com.apple.Notes", label: .productive),
        AppLabelRule(appName: "Notion", bundleIdentifier: "notion.id", label: .productive),
        AppLabelRule(appName: "Obsidian", bundleIdentifier: "md.obsidian", label: .productive),
        AppLabelRule(appName: "ChatGPT", bundleIdentifier: "com.openai.chat", label: .productive),
        AppLabelRule(appName: "Claude", bundleIdentifier: "com.anthropic.claudefordesktop", label: .productive),
        AppLabelRule(appName: "Safari", bundleIdentifier: "com.apple.Safari", label: .productive),
        AppLabelRule(appName: "Google Chrome", bundleIdentifier: "com.google.Chrome", label: .productive),
        AppLabelRule(appName: "Arc", bundleIdentifier: "company.thebrowser.Browser", label: .productive),
        AppLabelRule(appName: "Firefox", bundleIdentifier: "org.mozilla.firefox", label: .productive),
        AppLabelRule(appName: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap", label: .productive),
        AppLabelRule(appName: "Microsoft Teams", bundleIdentifier: "com.microsoft.teams2", label: .productive),
        AppLabelRule(appName: "Zoom", bundleIdentifier: "us.zoom.xos", label: .productive),
        AppLabelRule(appName: "Spotify", bundleIdentifier: "com.spotify.client", label: .unproductive),
        AppLabelRule(appName: "Music", bundleIdentifier: "com.apple.Music", label: .unproductive),
        AppLabelRule(appName: "TV", bundleIdentifier: "com.apple.TV", label: .unproductive),
        AppLabelRule(appName: "Podcasts", bundleIdentifier: "com.apple.podcasts", label: .unproductive),
        AppLabelRule(appName: "VLC", bundleIdentifier: "org.videolan.vlc", label: .unproductive),
        AppLabelRule(appName: "IINA", bundleIdentifier: "com.colliderli.iina", label: .unproductive)
    ]

    static func load() -> [AppLabelRule] {
        storedRules() ?? defaultRules
    }

    static func loadForSettings() -> [AppLabelRule] {
        trackingMode() == .manual ? manualTrackingRules() : load()
    }

    static func manualTrackingRules() -> [AppLabelRule] {
        storedRules(forKey: manualStorageKey) ?? []
    }

    static func trackingMode() -> AppTrackingMode {
        let rawValue = UserDefaults.standard.string(forKey: trackingModeKey)
        return rawValue.flatMap(AppTrackingMode.init(rawValue:)) ?? .all
    }

    static func rule(for bundleIdentifier: String, appName: String, in rules: [AppLabelRule]) -> AppLabelRule? {
        rules.first { rule in
            rule.isEnabled && (rule.bundleIdentifier == bundleIdentifier || appName.localizedCaseInsensitiveContains(rule.appName))
        }
    }

    static func save(_ rules: [AppLabelRule]) {
        saveRules(rules, forKey: storageKey)
        bumpRevision()
    }

    static func saveManualTrackingRules(_ rules: [AppLabelRule]) {
        saveRules(rules, forKey: manualStorageKey)
        bumpRevision()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: manualStorageKey)
        try? FileManager.default.removeItem(at: storageURL(forKey: storageKey))
        try? FileManager.default.removeItem(at: storageURL(forKey: manualStorageKey))
        bumpRevision()
    }

    static func bumpRevision() {
        UserDefaults.standard.set(UUID().uuidString, forKey: revisionKey)
    }

    private static func storedRules() -> [AppLabelRule]? {
        storedRules(forKey: storageKey)
    }

    private static func storedRules(forKey key: String) -> [AppLabelRule]? {
        let decoder = PropertyListDecoder()
        if let data = try? Data(contentsOf: storageURL(forKey: key)),
           let rules = try? decoder.decode([AppLabelRule].self, from: data) {
            return rules
        }

        guard let data = UserDefaults.standard.data(forKey: key),
              let rules = try? JSONDecoder().decode([AppLabelRule].self, from: data) else {
            return nil
        }

        saveRules(rules, forKey: key)
        return rules
    }

    private static func saveRules(_ rules: [AppLabelRule], forKey key: String) {
        do {
            let url = storageURL(forKey: key)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            let data = try encoder.encode(rules)
            try data.write(to: url, options: [.atomic])
            UserDefaults.standard.removeObject(forKey: key)
        } catch {}
    }

    private static func storageURL(forKey key: String) -> URL {
        let baseDirectory = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let fileName = key == manualStorageKey ? "manualTrackingRules" : "rules"

        return (baseDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent(ProductivityStorage.applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent("AppLabelRules", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
            .appendingPathExtension("labelrules")
    }
}
