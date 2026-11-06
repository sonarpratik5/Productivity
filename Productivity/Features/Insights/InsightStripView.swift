import SwiftUI

struct InsightStripView: View {
    let insights: [InsightSummary]
    @Environment(\.productivityTextScale) private var textScale

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12 * textScale) {
            ForEach(Array(insights.enumerated()), id: \.element.id) { index, insight in
                InsightCardView(insight: insight, isHero: index == 0)
                    .frame(maxWidth: .infinity, minHeight: 104 * textScale, alignment: .topLeading)
            }
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: 12 * textScale, alignment: .top),
            count: max(1, insights.count)
        )
    }
}

struct InsightCardView: View {
    let insight: InsightSummary
    var isHero: Bool = false
    @Environment(\.productivityTextScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(insight.category.tint)
                    .frame(width: 8, height: 8)
                Text(insight.title)
                    .productivityFont(.captionMedium)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(insight.value)
                .productivityFont(.metric)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(insight.trend)
                .productivityFont(.note)
                .foregroundStyle(ProductivityTheme.textSecondary)
                .lineLimit(1)
                .help(insight.trend)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14 * textScale)
        .background(
            isHero
                ? LinearGradient(
                    colors: [ProductivityTheme.elevatedBackground, ProductivityTheme.glow.opacity(0.38)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                : LinearGradient(
                    colors: [ProductivityTheme.elevatedBackground, ProductivityTheme.elevatedBackground],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHero ? insight.category.tint.opacity(0.30) : insight.category.tint.opacity(0.18),
                    lineWidth: isHero ? 1.5 : 1.0
                )
        )
    }
}
