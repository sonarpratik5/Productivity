import SwiftUI

struct SidebarView: View {
    @Binding var selection: DashboardRoute
    @Environment(\.productivityTextScale) private var textScale
    @State private var isAccountInfoVisible = false
    @AppStorage(AccountPreferenceKeys.displayName) private var displayName = AccountPreferenceKeys.defaultDisplayName
    @AppStorage(ProductivityTheme.storageKey) private var currentTheme = AppTheme.amethyst

    private var usesGlass: Bool { currentTheme == .crystal }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                navSection
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .scrollContentBackground(.hidden)

            Divider()
                .overlay(ProductivityTheme.border.opacity(0.45))

            accountFooter
        }
        .background(ProductivityTheme.elevatedBackground)
        .frame(minWidth: 150)
    }

    // Wraps nav rows in GlassEffectContainer on macOS 26+ / Crystal theme so the
    // glass capsule morphs fluidly between routes as the selection changes.
    @ViewBuilder
    private var navSection: some View {
        if #available(macOS 26.0, *), usesGlass {
            GlassEffectContainer(spacing: 6) {
                navRows
            }
        } else {
            navRows
        }
    }

    private var navRows: some View {
        VStack(spacing: 2) {
            SidebarNavRow(title: "Today", systemImage: "waveform.path.ecg.rectangle", route: .today, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarToday")
            SidebarNavRow(title: "Insights", systemImage: "chart.pie", route: .insights, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarInsights")
            SidebarNavRow(title: "Analytics", systemImage: "chart.xyaxis.line", route: .analytics, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarAnalytics")
            SidebarNavRow(title: "Board", systemImage: "calendar.badge.plus", route: .calendar, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarBoard")
            SidebarNavRow(title: "Pomodoro", systemImage: "timer", route: .pomodoro, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarPomodoro")
            SidebarNavRow(title: "Settings", systemImage: "gearshape", route: .settings, selection: $selection, textScale: textScale, usesGlass: usesGlass)
                .accessibilityIdentifier("SidebarSettings")
        }
    }

    private var accountFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isAccountInfoVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text(accountDisplayName)
                        .font(ProductivityTypography.font(.captionStrong, scale: textScale))
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text("Local workspace")
                        .font(ProductivityTypography.font(.note, scale: textScale))
                        .foregroundStyle(ProductivityTheme.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(FooterCardModifier(usesGlass: usesGlass, subtleOpacity: 1.0, glowOpacity: 0.56, borderOpacity: 0.55))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 10) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                ProductivityTheme.accent.opacity(0.28),
                                ProductivityTheme.accentSecondary.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        Text(accountInitials)
                            .font(ProductivityTypography.font(.noteStrong, scale: textScale))
                            .foregroundStyle(ProductivityTheme.accent)
                    }
                    .frame(width: 30 * textScale, height: 30 * textScale)

                VStack(alignment: .leading, spacing: 2) {
                    Text(accountDisplayName)
                        .font(ProductivityTypography.font(.captionStrong, scale: textScale))
                        .foregroundStyle(ProductivityTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()
            }
            .padding(10)
            .modifier(FooterCardModifier(usesGlass: usesGlass, subtleOpacity: 0.80, glowOpacity: 0.46, borderOpacity: 0.45))
        }
        .padding(12)
        .onHover { isHovering in
            withAnimation(.smooth(duration: 0.18)) {
                isAccountInfoVisible = isHovering
            }
        }
        .animation(.smooth(duration: 0.18), value: selection)
    }

    private var accountDisplayName: String {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Local Account" : trimmedName
    }

    private var accountInitials: String {
        let words = accountDisplayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let initials = String(words).uppercased()
        return initials.isEmpty ? "LA" : initials
    }
}

// MARK: - Nav row

private struct SidebarNavRow: View {
    let title: String
    let systemImage: String
    let route: DashboardRoute
    @Binding var selection: DashboardRoute
    let textScale: CGFloat
    let usesGlass: Bool

    private var isSelected: Bool { selection == route }

    var body: some View {
        Button { selection = route } label: {
            Label(title, systemImage: systemImage)
                .font(ProductivityTypography.font(.controlLabel, scale: textScale))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .modifier(NavRowBackgroundModifier(isSelected: isSelected, usesGlass: usesGlass))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(
            isSelected ? ProductivityTheme.accent : ProductivityTheme.textPrimary
        )
    }
}

// MARK: - Modifiers

/// On Crystal + macOS 26: applies Liquid Glass to the selected row so it morphs
/// between routes inside the parent GlassEffectContainer.
/// On all other themes / older macOS: falls back to the accent-tint fill.
private struct NavRowBackgroundModifier: ViewModifier {
    let isSelected: Bool
    let usesGlass: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesGlass {
            if isSelected {
                content
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                content
            }
        } else {
            content
                .background(
                    isSelected ? ProductivityTheme.accent.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
    }
}

/// On Crystal + macOS 26: wraps footer cards in Liquid Glass.
/// Otherwise uses the original gradient-card appearance.
private struct FooterCardModifier: ViewModifier {
    let usesGlass: Bool
    let subtleOpacity: Double
    let glowOpacity: Double
    let borderOpacity: Double

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesGlass {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
                .background(
                    LinearGradient(
                        colors: [
                            ProductivityTheme.subtleBackground.opacity(subtleOpacity),
                            ProductivityTheme.glow.opacity(glowOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ProductivityTheme.border.opacity(borderOpacity), lineWidth: 1)
                )
        }
    }
}

#if DEBUG
#Preview {
    SidebarView(selection: .constant(.today))
        .frame(width: 240, height: 560)
        .preferredColorScheme(.dark)
}
#endif
