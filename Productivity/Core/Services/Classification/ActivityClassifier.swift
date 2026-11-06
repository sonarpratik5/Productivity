import Foundation

protocol ActivityClassifying {
    func label(for bundleIdentifier: String, appName: String) -> ActivityLabel
    func category(for bundleIdentifier: String, appName: String) -> ActivityCategory
    func productivityScore(for category: ActivityCategory) -> Double
}

struct RuleBasedActivityClassifier: ActivityClassifying {
    private let labelRules: [AppLabelRule]?
    private let selfBundleIdentifier: String?
    private let bundleRules: [String: ActivityCategory] = [
        "com.apple.dt.Xcode": .focus,
        "com.microsoft.VSCode": .focus,
        "com.apple.Terminal": .focus,
        "com.googlecode.iterm2": .focus,
        "com.apple.Notes": .focus,
        "notion.id": .focus,
        "md.obsidian": .focus,
        "com.openai.chat": .research,
        "com.anthropic.claudefordesktop": .research,
        "com.tinyspeck.slackmacgap": .communication,
        "com.microsoft.teams2": .communication,
        "us.zoom.xos": .communication,
        "com.spotify.client": .entertainment,
        "com.apple.Music": .entertainment,
        "com.apple.TV": .entertainment,
        "com.apple.podcasts": .entertainment,
        "org.videolan.vlc": .entertainment,
        "com.colliderli.iina": .entertainment,
        "com.apple.Safari": .research,
        "com.google.Chrome": .research,
        "company.thebrowser.Browser": .research,
        "org.mozilla.firefox": .research,
        "com.apple.finder": .system
    ]

    init(labelRules: [AppLabelRule]? = nil, selfBundleIdentifier: String? = nil) {
        self.labelRules = labelRules
        self.selfBundleIdentifier = selfBundleIdentifier
    }

    func label(for bundleIdentifier: String, appName: String) -> ActivityLabel {
        // This app itself is always a productive focus activity.
        if let selfBundleIdentifier, bundleIdentifier == selfBundleIdentifier {
            return .focus
        }

        let currentRules = labelRules ?? (
            AppLabelRuleStore.trackingMode() == .manual
                ? AppLabelRuleStore.manualTrackingRules()
                : AppLabelRuleStore.load()
        )
        if let labelRule = AppLabelRuleStore.rule(for: bundleIdentifier, appName: appName, in: currentRules) {
            return labelRule.label
        }

        return ActivityLabel.from(category: bundleRules[bundleIdentifier] ?? .unknown)
    }

    func category(for bundleIdentifier: String, appName: String) -> ActivityCategory {
        label(for: bundleIdentifier, appName: appName).category
    }

    func productivityScore(for category: ActivityCategory) -> Double {
        switch category {
        case .focus: 1.0
        case .research: 0.75
        case .communication: 0.65
        case .system: 0.2
        case .unknown: 0.2
        case .entertainment: 0.05
        }
    }

}
