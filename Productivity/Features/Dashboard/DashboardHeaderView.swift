import SwiftUI

struct DashboardHeaderView: View {
    let overview: DailyActivityOverview
    let trackingStatus: ActivityTrackingStatus
    let metricSegments: [ActivitySegment]

    @Environment(\.productivityTextScale) private var textScale
    @AppStorage(AppLabelRuleStore.trackingModeKey) private var appTrackingMode = AppTrackingMode.all
    @AppStorage(AppPreferenceKeys.productivityThresholdPercent) private var productivityThresholdPercent = 70

    var body: some View {
        let latestSegment = latestSegment

        HStack(alignment: .center, spacing: 20) {
            HStack(alignment: .center, spacing: 8) {
                Text("Today")
                    .productivityFont(.hero)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                ProductivityInfoHint(message: "Live activity across apps, with recent capture status and current productivity ratio.")
            }

            Spacer()

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    trackingPill
                    latestActivityPill(latestSegment: latestSegment)
                    productivityScore(latestSegment: latestSegment)
                }

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 10) {
                        trackingPill
                        productivityScore(latestSegment: latestSegment)
                    }
                    latestActivityPill(latestSegment: latestSegment)
                }
            }
        }
    }

    private var trackingPill: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusTitle)
                .productivityFont(.bodyMedium)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ProductivityTheme.subtleBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.5), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func latestActivityPill(latestSegment: ActivitySegment?) -> some View {
        if let latestSegment {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(latestSegment.category.tint)
                    .frame(width: 8, height: 18)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Last captured")
                        .productivityFont(.noteMedium)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                    Text(latestActivitySummaryText(for: latestSegment))
                        .productivityFont(.captionStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 210, alignment: .leading)
            .background(ProductivityTheme.subtleBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
        } else if trackingStatus != .paused {
            HStack(spacing: 8) {
                statusIcon
                VStack(alignment: .leading, spacing: 1) {
                    Text("Last captured")
                        .productivityFont(.noteMedium)
                        .foregroundStyle(ProductivityTheme.textSecondary)
                    Text(latestStatusText)
                        .productivityFont(.captionStrong)
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 210, alignment: .leading)
            .background(ProductivityTheme.subtleBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(ProductivityTheme.border.opacity(0.45), lineWidth: 1)
            )
        }
    }

    private var productivityScoreColor: Color {
        let percent = Int(overview.productivityRatio * 100)
        return percent >= productivityThresholdPercent
            ? ActivityLabel.productive.tint
            : ActivityLabel.unproductive.tint
    }

    private func productivityScore(latestSegment: ActivitySegment?) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text("\(Int(overview.productivityRatio * 100))%")
                .font(ProductivityTypography.font(.metricHero, scale: textScale * (32 / 34)))
                .foregroundStyle(productivityScoreColor)
            Text(productivityStatusTitle(for: latestSegment))
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
    }

    private var latestSegment: ActivitySegment? {
        let referenceDate = overview.date
        return metricSegments.reduce(nil) { latest, segment in
            guard !segment.isLifecycleContext, !segment.isSleepEvent else { return latest }
            guard segment.startDate < referenceDate else { return latest }
            guard let latest else { return segment }

            let segmentEnd = min(segment.endDate, referenceDate)
            let latestEnd = min(latest.endDate, referenceDate)
            if segmentEnd == latestEnd {
                return segment.startDate > latest.startDate ? segment : latest
            }
            return segmentEnd > latestEnd ? segment : latest
        }
    }

    private func latestActivitySummaryText(for segment: ActivitySegment) -> String {
        let endDate = min(segment.endDate, overview.date)
        let duration = max(0, endDate.timeIntervalSince(segment.startDate))
        return "\(segment.appName) · \(DurationFormatting.abbreviated(duration))"
    }

    private func productivityStatusTitle(for latestSegment: ActivitySegment?) -> String {
        guard let latestSegment else { return "productivity" }
        let isCurrent = latestSegment.startDate <= overview.date && overview.date < latestSegment.endDate
        let prefix = isCurrent ? "current" : "latest"
        switch latestSegment.label.commonRollup {
        case .productive:
            return "\(prefix) productive"
        case .unproductive:
            return "\(prefix) unproductive"
        case .unknown:
            return "\(prefix) unknown"
        default:
            return "\(prefix) unknown"
        }
    }

    private var statusTitle: String {
        switch trackingStatus {
        case .paused: "Paused"
        case .starting: "Starting"
        case .tracking: "Tracking"
        case .waitingForTrackedApp: "Waiting"
        }
    }

    private var latestStatusText: String {
        switch trackingStatus {
        case .paused: "Tracking paused"
        case .starting: "Starting tracker"
        case .tracking: "Waiting for next update"
        case .waitingForTrackedApp: appTrackingMode == .manual ? "Manual mode: app not selected" : "No tracked app active"
        }
    }

    private var statusColor: Color {
        switch trackingStatus {
        case .paused: ProductivityTheme.textSecondary
        case .starting: ProductivityTheme.accent
        case .tracking: ActivityLabel.productive.tint
        case .waitingForTrackedApp: ActivityLabel.unknown.tint
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if trackingStatus == .starting {
            ProgressView()
                .controlSize(.small)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
        }
    }
}
