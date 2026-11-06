import SwiftUI

enum ActivityCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case focus
    case communication
    case research
    case entertainment
    case system
    case unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: "Focus"
        case .communication: "Communication"
        case .research: "Research"
        case .entertainment: "Entertainment"
        case .system: "System"
        case .unknown: "Unknown"
        }
    }

    var tint: Color {
        switch self {
        case .focus: Color(red: 0.18, green: 0.61, blue: 0.56)
        case .communication: Color(red: 0.38, green: 0.56, blue: 0.92)
        case .research: Color(red: 0.78, green: 0.58, blue: 0.24)
        case .entertainment: Color(red: 1.00, green: 0.55, blue: 0.35)
        case .system: Color(red: 0.42, green: 0.50, blue: 0.52)
        case .unknown: Color(red: 0.60, green: 0.63, blue: 0.64)
        }
    }
}
