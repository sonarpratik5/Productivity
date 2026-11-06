import SwiftUI

extension ActivityLabelDefinition {
    var tint: Color { Color(red: red, green: green, blue: blue) }
}

extension ActivityLabelColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension ActivityLabel {
    @MainActor var tint: Color {
        if case .sleep = self { return ActivityLabelColor.sleep.color }
        return ActivityLabelColor(rollup: commonRollup).color
    }
}
