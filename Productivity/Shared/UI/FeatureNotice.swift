import SwiftUI

struct FeatureNotice: Equatable {
    let title: String
    let message: String

    static func incomplete(_ message: String) -> FeatureNotice {
        FeatureNotice(title: "Feature incomplete", message: message)
    }
}

struct FeatureNoticeModifier: ViewModifier {
    @Binding var notice: FeatureNotice?

    func body(content: Content) -> some View {
        ZStack(alignment: .topTrailing) {
            content

            if let notice {
                FeatureNoticeView(notice: notice)
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.22), value: notice)
    }
}

extension View {
    func featureNotice(_ notice: Binding<FeatureNotice?>) -> some View {
        modifier(FeatureNoticeModifier(notice: notice))
    }
}

private struct FeatureNoticeView: View {
    let notice: FeatureNotice

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .productivityFont(.bodyStrong)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            ProductivityTheme.accent,
                            ProductivityTheme.accentSecondary
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(notice.title)
                    .productivityFont(.captionStrong)
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text(notice.message)
                    .productivityFont(.note)
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 280, alignment: .leading)
        .background(
            ProductivityTheme.elevatedBackground,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(ProductivityTheme.border.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: ProductivityTheme.accentSecondary.opacity(0.12), radius: 18, y: 10)
    }
}
