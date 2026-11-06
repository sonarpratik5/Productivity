import AppKit
import SwiftUI
import UserNotifications

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("productivity.hasCompletedPermissionsOnboarding") private var hasCompletedOnboarding = false
    @State private var showPermissionsOnboarding = false

    var body: some View {
        ZStack {
            ProductivityTheme.background
                .ignoresSafeArea()

            DashboardView(environment: environment)
        }
        .observeProductivityWindowPresentation()
        .accessibilityIdentifier("DashboardRoot")
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar(removing: .title)
        .task {
            guard !hasCompletedOnboarding else { return }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                showPermissionsOnboarding = true
            } else {
                hasCompletedOnboarding = true
            }
        }
        .sheet(isPresented: $showPermissionsOnboarding) {
            PermissionsOnboardingView {
                hasCompletedOnboarding = true
                showPermissionsOnboarding = false
            }
        }
    }
}

// MARK: - Onboarding sheet

private struct PermissionsOnboardingView: View {
    let onComplete: () -> Void

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @AppStorage(ProductivityTheme.storageKey) private var currentTheme = AppTheme.amethyst

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ProductivityTheme.border.opacity(0.4))
            permissionsList
            Divider().overlay(ProductivityTheme.border.opacity(0.4))
            actionBar
        }
        .frame(width: 460)
        .background(ProductivityTheme.background)
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text("Welcome to FocusGrove")
                .font(ProductivityTypography.font(.metricProminent))
                .foregroundStyle(ProductivityTheme.textPrimary)

            Text("Allow the following so the app can work as intended. You can change these anytime in System Settings.")
                .font(ProductivityTypography.font(.body))
                .foregroundStyle(ProductivityTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }

    private var permissionsList: some View {
        VStack(spacing: 10) {
            permissionRow(
                icon: "bell.badge",
                title: "Notifications",
                description: "Delivers reminders for your manually planned activity events at the time you choose.",
                status: notificationStatus
            )
        }
        .padding(24)
    }

    private var actionBar: some View {
        HStack {
            Button("Skip for Now") {
                onComplete()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(ProductivityTheme.textSecondary)

            Spacer()

            if notificationStatus == .authorized || notificationStatus == .provisional {
                Button("Continue") { onComplete() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Grant Notification Access") {
                    Task {
                        let granted = (try? await UNUserNotificationCenter.current()
                            .requestAuthorization(options: [.alert, .sound])) ?? false
                        notificationStatus = granted ? .authorized : .denied
                        onComplete()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }

    private func permissionRow(
        icon: String,
        title: String,
        description: String,
        status: UNAuthorizationStatus
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ProductivityTheme.accent)
                .frame(width: 38, height: 38)
                .background(ProductivityTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(ProductivityTypography.font(.bodyMedium))
                    .foregroundStyle(ProductivityTheme.textPrimary)
                Text(description)
                    .font(ProductivityTypography.font(.note))
                    .foregroundStyle(ProductivityTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statusBadge(for: status)
                .padding(.top, 2)
        }
        .padding(14)
        .background(ProductivityTheme.subtleBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(ProductivityTheme.border.opacity(0.28), lineWidth: 1))
    }

    @ViewBuilder
    private func statusBadge(for status: UNAuthorizationStatus) -> some View {
        switch status {
        case .authorized, .provisional:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(ProductivityTypography.font(.noteStrong))
                .foregroundStyle(.green)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .font(ProductivityTypography.font(.noteStrong))
                .foregroundStyle(.red)
        default:
            Label("Recommended", systemImage: "circle.dotted")
                .font(ProductivityTypography.font(.noteStrong))
                .foregroundStyle(ProductivityTheme.textSecondary)
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .environment(AppEnvironment.preview())
}
#endif
