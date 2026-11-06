import WidgetKit
import SwiftUI

@main
struct ProductivityWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ProductivityOverviewWidget()
        TodayGoalsWidget()
    }
}
