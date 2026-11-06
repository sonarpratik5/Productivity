import SwiftUI

struct DailyQuoteHeaderView: View {
    @AppStorage(AppPreferenceKeys.customMotivationQuote) private var customQuote = ""
    @Environment(\.productivityTextScale) private var textScale
    @State private var quoteDate = Date()

    private var trimmedCustomQuote: String {
        customQuote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isShowingCustomQuote: Bool {
        !trimmedCustomQuote.isEmpty
    }

    private var quote: String {
        if isShowingCustomQuote {
            return trimmedCustomQuote
        }

        return DailyQuoteProvider.quote(for: quoteDate)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = DailyQuoteMetrics(width: proxy.size.width, textScale: textScale)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .font(
                            ProductivityTypography.font(
                                .noteStrong,
                                scale: metrics.eyebrowFontSize / 12.5
                            )
                        )
                        .foregroundStyle(ProductivityTheme.accent)
                    Text("Daily focus")
                        .font(
                            ProductivityTypography.font(
                                .noteStrong,
                                scale: metrics.eyebrowFontSize / 12.5
                            )
                        )
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }

                Text(quote)
                    .font(
                        ProductivityTypography.font(
                            .heroSupporting,
                            scale: metrics.quoteFontSize / 22
                        )
                    )
                    .foregroundStyle(ProductivityTheme.textPrimary)
                    .lineLimit(metrics.quoteLineLimit)
                    .minimumScaleFactor(0.72)

                Text(isShowingCustomQuote ? "Your custom note" : "Refreshes every day")
                    .productivitySupportingNoteStyle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(metrics.padding)
            .background(
                LinearGradient(
                    colors: [
                        ProductivityTheme.elevatedBackground,
                        ProductivityTheme.glow.opacity(0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
            .overlay(alignment: .bottomLeading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                ProductivityTheme.accent.opacity(0.92),
                                ProductivityTheme.accentSecondary.opacity(0.85)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: min(240, proxy.size.width * 0.42), height: 4)
                    .padding(.leading, metrics.padding)
                    .padding(.bottom, 2)
            }
        }
        .frame(minHeight: 132 * textScale)
        .task {
            await refreshQuoteDateAtLocalMidnight()
        }
    }

    private func refreshQuoteDateAtLocalMidnight(calendar: Calendar = .current) async {
        quoteDate = Date()

        while !Task.isCancelled {
            let now = Date()
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
                return
            }

            let nanosecondsUntilNextDay = UInt64(max(1, nextDay.timeIntervalSince(now)) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanosecondsUntilNextDay)
            } catch {
                return
            }

            quoteDate = Date()
        }
    }
}

private enum DailyQuoteProvider {
    private static let quotes = [
        "Make today measurable, not perfect.",
        "Small focus compounds into real progress.",
        "Protect the next block of attention.",
        "Start with the work that changes the day.",
        "Clarity first, momentum next.",
        "Let the timeline show honest progress.",
        "One focused session can reset the day.",
        "Choose the task that makes everything lighter.",
        "Reduce the noise, then move.",
        "Build the day one useful block at a time."
    ]

    static func quote(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let seed = ((components.year ?? 0) * 372) + ((components.month ?? 0) * 31) + (components.day ?? 0)
        let index = abs(seed) % quotes.count
        return quotes[index]
    }
}

private struct DailyQuoteMetrics {
    let width: CGFloat
    let textScale: CGFloat

    var padding: CGFloat { (width < 680 ? 16 : 20) * textScale }
    var quoteFontSize: CGFloat { (width < 680 ? 22 : 27) * textScale }
    var eyebrowFontSize: CGFloat { (width < 680 ? 12 : 13) * textScale }
    var quoteLineLimit: Int { width < 760 ? 3 : 2 }
}

#if DEBUG
#Preview {
    DailyQuoteHeaderView()
        .padding(28)
        .frame(width: 520, height: 210)
        .background(ProductivityTheme.background)
        .preferredColorScheme(.dark)
}
#endif
