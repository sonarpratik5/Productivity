import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case amethyst
    case iris
    case paper
    case crystal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amethyst: "Amethyst"
        case .iris: "Iris"
        case .paper: "Paper"
        case .crystal: "Crystal"
        }
    }

    var subtitle: String {
        switch self {
        case .amethyst:
            "The default Amethyst palette: warm ivory space, ink-teal structure, mint energy, and coral signals."
        case .iris:
            "A violet-indigo palette with lavender surfaces, deep purple-black depth, and vibrant iris accent — inspired by Linear and Raycast."
        case .paper:
            "A paper-toned, Notion-inspired editorial theme with warmer neutrals and softer contrast."
        case .crystal:
            "Liquid Glass-inspired: pristine neutral surfaces, crystal cyan refraction, and true glass morphing navigation on macOS 26+."
        }
    }
}

enum ProductivityTheme {
    static let storageKey = "app.theme"
    static let panelCornerRadius: CGFloat = 10
    static let innerCardCornerRadius: CGFloat = 8
    static let chipCornerRadius: CGFloat = 6
    static let laneHeight: CGFloat = 18
    static let contentMaxWidth: CGFloat = 1280
    static let wideContentMaxWidth: CGFloat = 1760
    static let fullScreenContentMaxWidth: CGFloat = 2280

    static var background: Color {
        Color(nsColor: backgroundNSColor)
    }

    static var backgroundNSColor: NSColor {
        adaptiveNSColor(light: palette.backgroundLight, dark: palette.backgroundDark)
    }

    static var elevatedBackground: Color {
        adaptiveColor(light: palette.elevatedBackgroundLight, dark: palette.elevatedBackgroundDark)
    }

    static var subtleBackground: Color {
        adaptiveColor(light: palette.subtleBackgroundLight, dark: palette.subtleBackgroundDark)
    }

    static var border: Color {
        adaptiveColor(light: palette.borderLight, dark: palette.borderDark)
    }

    static var textPrimary: Color {
        adaptiveColor(light: palette.textPrimaryLight, dark: palette.textPrimaryDark)
    }

    static var textSecondary: Color {
        adaptiveColor(light: palette.textSecondaryLight, dark: palette.textSecondaryDark)
    }

    static var accent: Color {
        palette.accent
    }

    static var accentSecondary: Color {
        palette.accentSecondary
    }

    static var accentTertiary: Color {
        palette.accentTertiary
    }

    static var glow: Color {
        adaptiveColor(light: palette.glowLight, dark: palette.glowDark)
    }

    static func contentWidth(for availableWidth: CGFloat, isFullScreen: Bool = false) -> CGFloat {
        let maxWidth: CGFloat

        if isFullScreen {
            switch availableWidth {
            case ..<1380:
                maxWidth = contentMaxWidth
            case ..<1780:
                maxWidth = 1600
            case ..<2200:
                maxWidth = 1960
            default:
                maxWidth = fullScreenContentMaxWidth
            }
        } else {
            switch availableWidth {
            case ..<1380:
                maxWidth = contentMaxWidth
            case ..<1720:
                maxWidth = 1520
            default:
                maxWidth = wideContentMaxWidth
            }
        }

        let padding = contentPadding(for: availableWidth, isFullScreen: isFullScreen)
        return min(max(availableWidth - (padding * 2), 0), maxWidth)
    }

    static func contentPadding(for availableWidth: CGFloat, isFullScreen: Bool = false) -> CGFloat {
        if isFullScreen {
            return min(max(availableWidth * 0.018, 20), 32)
        }

        return min(max(availableWidth * 0.026, 24), 44)
    }

    private static var selectedTheme: AppTheme {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppTheme.init(rawValue:)) ?? .amethyst
    }

    private static var palette: ThemePalette {
        switch selectedTheme {
        case .amethyst:
            ThemePalette(
                backgroundLight: NSColor(calibratedRed: 0.964, green: 0.953, blue: 0.928, alpha: 1),
                backgroundDark: NSColor(calibratedRed: 0.047, green: 0.094, blue: 0.110, alpha: 1),
                elevatedBackgroundLight: NSColor(calibratedRed: 0.992, green: 0.987, blue: 0.973, alpha: 1),
                elevatedBackgroundDark: NSColor(calibratedRed: 0.071, green: 0.129, blue: 0.153, alpha: 1),
                subtleBackgroundLight: NSColor(calibratedRed: 0.916, green: 0.945, blue: 0.935, alpha: 1),
                subtleBackgroundDark: NSColor(calibratedRed: 0.098, green: 0.180, blue: 0.208, alpha: 1),
                borderLight: NSColor(calibratedRed: 0.788, green: 0.839, blue: 0.820, alpha: 1),
                borderDark: NSColor(calibratedRed: 0.204, green: 0.337, blue: 0.376, alpha: 1),
                textPrimaryLight: NSColor(calibratedRed: 0.082, green: 0.180, blue: 0.220, alpha: 1),
                textPrimaryDark: NSColor(calibratedRed: 0.904, green: 0.931, blue: 0.917, alpha: 1),
                textSecondaryLight: NSColor(calibratedRed: 0.337, green: 0.431, blue: 0.447, alpha: 1),
                textSecondaryDark: NSColor(calibratedRed: 0.588, green: 0.686, blue: 0.702, alpha: 1),
                accent: Color(red: 0.176, green: 0.608, blue: 0.561),
                accentSecondary: Color(red: 1.000, green: 0.553, blue: 0.349),
                accentTertiary: Color(red: 0.118, green: 0.341, blue: 0.396),
                glowLight: NSColor(calibratedRed: 0.870, green: 0.969, blue: 0.944, alpha: 1),
                glowDark: NSColor(calibratedRed: 0.102, green: 0.235, blue: 0.267, alpha: 1)
            )
        case .iris:
            ThemePalette(
                backgroundLight: NSColor(calibratedRed: 0.966, green: 0.962, blue: 0.976, alpha: 1),
                backgroundDark: NSColor(calibratedRed: 0.059, green: 0.047, blue: 0.110, alpha: 1),
                elevatedBackgroundLight: NSColor(calibratedRed: 0.994, green: 0.992, blue: 0.999, alpha: 1),
                elevatedBackgroundDark: NSColor(calibratedRed: 0.086, green: 0.071, blue: 0.153, alpha: 1),
                subtleBackgroundLight: NSColor(calibratedRed: 0.908, green: 0.902, blue: 0.941, alpha: 1),
                subtleBackgroundDark: NSColor(calibratedRed: 0.129, green: 0.114, blue: 0.216, alpha: 1),
                borderLight: NSColor(calibratedRed: 0.784, green: 0.773, blue: 0.851, alpha: 1),
                borderDark: NSColor(calibratedRed: 0.224, green: 0.208, blue: 0.365, alpha: 1),
                textPrimaryLight: NSColor(calibratedRed: 0.106, green: 0.094, blue: 0.188, alpha: 1),
                textPrimaryDark: NSColor(calibratedRed: 0.906, green: 0.898, blue: 0.957, alpha: 1),
                textSecondaryLight: NSColor(calibratedRed: 0.416, green: 0.404, blue: 0.537, alpha: 1),
                textSecondaryDark: NSColor(calibratedRed: 0.612, green: 0.600, blue: 0.749, alpha: 1),
                accent: Color(red: 0.486, green: 0.357, blue: 0.984),
                accentSecondary: Color(red: 0.961, green: 0.647, blue: 0.137),
                accentTertiary: Color(red: 0.224, green: 0.157, blue: 0.549),
                glowLight: NSColor(calibratedRed: 0.906, green: 0.894, blue: 0.984, alpha: 1),
                glowDark: NSColor(calibratedRed: 0.118, green: 0.098, blue: 0.235, alpha: 1)
            )
        case .paper:
            ThemePalette(
                backgroundLight: NSColor(calibratedRed: 0.962, green: 0.957, blue: 0.946, alpha: 1),
                backgroundDark: NSColor(calibratedRed: 0.072, green: 0.094, blue: 0.106, alpha: 1),
                elevatedBackgroundLight: NSColor(calibratedRed: 0.989, green: 0.986, blue: 0.978, alpha: 1),
                elevatedBackgroundDark: NSColor(calibratedRed: 0.089, green: 0.114, blue: 0.129, alpha: 1),
                subtleBackgroundLight: NSColor(calibratedRed: 0.924, green: 0.938, blue: 0.935, alpha: 1),
                subtleBackgroundDark: NSColor(calibratedRed: 0.122, green: 0.149, blue: 0.161, alpha: 1),
                borderLight: NSColor(calibratedRed: 0.786, green: 0.820, blue: 0.812, alpha: 1),
                borderDark: NSColor(calibratedRed: 0.263, green: 0.306, blue: 0.322, alpha: 1),
                textPrimaryLight: NSColor(calibratedRed: 0.106, green: 0.180, blue: 0.204, alpha: 1),
                textPrimaryDark: NSColor(calibratedRed: 0.912, green: 0.926, blue: 0.922, alpha: 1),
                textSecondaryLight: NSColor(calibratedRed: 0.374, green: 0.420, blue: 0.427, alpha: 1),
                textSecondaryDark: NSColor(calibratedRed: 0.655, green: 0.698, blue: 0.706, alpha: 1),
                accent: Color(red: 0.188, green: 0.592, blue: 0.529),
                accentSecondary: Color(red: 0.365, green: 0.635, blue: 0.780),
                accentTertiary: Color(red: 0.173, green: 0.333, blue: 0.373),
                glowLight: NSColor(calibratedRed: 0.888, green: 0.954, blue: 0.944, alpha: 1),
                glowDark: NSColor(calibratedRed: 0.145, green: 0.204, blue: 0.220, alpha: 1)
            )
        case .crystal:
            ThemePalette(
                // Pristine cool-white surfaces — the neutral "glass substrate" in light
                backgroundLight: NSColor(calibratedRed: 0.949, green: 0.949, blue: 0.969, alpha: 1),
                // Deep blue-black — looking through dark glass in dark mode
                backgroundDark: NSColor(calibratedRed: 0.039, green: 0.043, blue: 0.071, alpha: 1),
                // Pure white elevated surface — clear glass sitting on light
                elevatedBackgroundLight: NSColor(calibratedRed: 1.000, green: 1.000, blue: 1.000, alpha: 1),
                // Lifted dark layer with subtle blue depth
                elevatedBackgroundDark: NSColor(calibratedRed: 0.106, green: 0.110, blue: 0.141, alpha: 1),
                // Subtle cool-gray fill for chips and tags
                subtleBackgroundLight: NSColor(calibratedRed: 0.898, green: 0.902, blue: 0.922, alpha: 1),
                // Mid-dark with blue glass tint
                subtleBackgroundDark: NSColor(calibratedRed: 0.165, green: 0.169, blue: 0.208, alpha: 1),
                // Crisp, cool border — like the light edge of glass
                borderLight: NSColor(calibratedRed: 0.780, green: 0.784, blue: 0.808, alpha: 1),
                // Subtle blue-gray border in dark
                borderDark: NSColor(calibratedRed: 0.227, green: 0.231, blue: 0.282, alpha: 1),
                // Apple's rich near-black — maximum legibility on bright glass
                textPrimaryLight: NSColor(calibratedRed: 0.110, green: 0.110, blue: 0.118, alpha: 1),
                // Near-white with tiny blue cast — clean on dark glass
                textPrimaryDark: NSColor(calibratedRed: 0.961, green: 0.961, blue: 0.969, alpha: 1),
                // Apple's neutral secondary gray
                textSecondaryLight: NSColor(calibratedRed: 0.557, green: 0.557, blue: 0.576, alpha: 1),
                // Cool gray secondary in dark
                textSecondaryDark: NSColor(calibratedRed: 0.588, green: 0.592, blue: 0.635, alpha: 1),
                // Crystal cyan — refracted light through clear glass
                accent: Color(red: 0.024, green: 0.714, blue: 0.831),
                // Warm amber — the complementary warm refraction
                accentSecondary: Color(red: 0.976, green: 0.451, blue: 0.086),
                // Deep ocean teal — glass at depth
                accentTertiary: Color(red: 0.055, green: 0.455, blue: 0.565),
                // Soft cyan shimmer in light
                glowLight: NSColor(calibratedRed: 0.812, green: 0.980, blue: 0.996, alpha: 1),
                // Deep ocean glow in dark
                glowDark: NSColor(calibratedRed: 0.031, green: 0.200, blue: 0.267, alpha: 1)
            )
        }
    }

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            let matchedAppearance = appearance.bestMatch(from: [.aqua, .darkAqua])
            return matchedAppearance == .darkAqua ? dark : light
        }
    }
}

private struct ProductivityTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private struct ProductivityFullScreenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var productivityTextScale: CGFloat {
        get { self[ProductivityTextScaleKey.self] }
        set { self[ProductivityTextScaleKey.self] = newValue }
    }

    var productivityIsFullScreen: Bool {
        get { self[ProductivityFullScreenKey.self] }
        set { self[ProductivityFullScreenKey.self] = newValue }
    }
}

enum ProductivityFontStyle {
    case hero
    case heroSupporting
    case sectionTitle
    case sectionLabel
    case body
    case bodyStrong
    case bodyMedium
    case bodyMonospaced
    case caption
    case captionStrong
    case captionMedium
    case captionMonospaced
    case note
    case noteStrong
    case noteMedium
    case noteMonospaced
    case metric
    case metricProminent
    case metricHero
    case metricHeroMonospaced
    case metricMonospaced
    case controlLabel
    case controlIcon
}

enum ProductivityTypography {
    static func font(
        _ style: ProductivityFontStyle,
        scale: CGFloat = 1,
        weight: Font.Weight? = nil
    ) -> Font {
        let resolvedScale = max(scale, 0.85)
        let specification = specification(for: style)
        let font = Font.system(
            size: max(specification.size * resolvedScale, specification.minimumSize),
            weight: weight ?? specification.weight,
            design: specification.design
        )

        if specification.monospacedDigits {
            return font.monospacedDigit()
        }

        return font
    }

    private static func specification(for style: ProductivityFontStyle) -> ProductivityFontSpecification {
        switch style {
        case .hero:
            ProductivityFontSpecification(size: 24, minimumSize: 22, weight: .semibold, design: .rounded)
        case .heroSupporting:
            ProductivityFontSpecification(size: 17, minimumSize: 16, weight: .semibold, design: .rounded)
        case .sectionTitle:
            ProductivityFontSpecification(size: 14, minimumSize: 13.5, weight: .semibold)
        case .sectionLabel:
            ProductivityFontSpecification(size: 13, minimumSize: 12.5, weight: .semibold)
        case .body:
            ProductivityFontSpecification(size: 14, minimumSize: 13.5, weight: .regular)
        case .bodyStrong:
            ProductivityFontSpecification(size: 14, minimumSize: 13.5, weight: .semibold)
        case .bodyMedium:
            ProductivityFontSpecification(size: 14, minimumSize: 13.5, weight: .medium)
        case .bodyMonospaced:
            ProductivityFontSpecification(size: 14, minimumSize: 13.5, weight: .regular, monospacedDigits: true)
        case .caption:
            ProductivityFontSpecification(size: 12.5, minimumSize: 12, weight: .regular)
        case .captionStrong:
            ProductivityFontSpecification(size: 12.5, minimumSize: 12, weight: .semibold)
        case .captionMedium:
            ProductivityFontSpecification(size: 12.5, minimumSize: 12, weight: .medium)
        case .captionMonospaced:
            ProductivityFontSpecification(size: 12.5, minimumSize: 12, weight: .regular, monospacedDigits: true)
        case .note:
            ProductivityFontSpecification(size: 12, minimumSize: 12, weight: .regular)
        case .noteStrong:
            ProductivityFontSpecification(size: 12, minimumSize: 12, weight: .semibold)
        case .noteMedium:
            ProductivityFontSpecification(size: 12, minimumSize: 12, weight: .medium)
        case .noteMonospaced:
            ProductivityFontSpecification(size: 12, minimumSize: 12, weight: .medium, monospacedDigits: true)
        case .metric:
            ProductivityFontSpecification(size: 20, minimumSize: 18, weight: .semibold, design: .rounded)
        case .metricProminent:
            ProductivityFontSpecification(size: 22, minimumSize: 20, weight: .semibold, design: .rounded)
        case .metricHero:
            ProductivityFontSpecification(size: 24, minimumSize: 22, weight: .semibold, design: .rounded)
        case .metricHeroMonospaced:
            ProductivityFontSpecification(size: 32, minimumSize: 28, weight: .semibold, design: .rounded, monospacedDigits: true)
        case .metricMonospaced:
            ProductivityFontSpecification(size: 20, minimumSize: 18, weight: .semibold, design: .rounded, monospacedDigits: true)
        case .controlLabel:
            ProductivityFontSpecification(size: 12.5, minimumSize: 12, weight: .medium)
        case .controlIcon:
            ProductivityFontSpecification(size: 14, minimumSize: 13, weight: .semibold)
        }
    }
}

private struct ProductivitySupportingTextModifier: ViewModifier {
    @Environment(\.productivityTextScale) private var textScale

    let compact: Bool

    func body(content: Content) -> some View {
        let baseSize: CGFloat = compact ? 12.5 : 14

        content
            .font(
                ProductivityTypography.font(
                    compact ? .noteMedium : .caption,
                    scale: compact ? textScale : textScale * (baseSize / 13.5)
                )
            )
            .foregroundStyle(ProductivityTheme.textSecondary.opacity(compact ? 0.88 : 0.94))
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProductivityFontModifier: ViewModifier {
    @Environment(\.productivityTextScale) private var textScale

    let style: ProductivityFontStyle
    let scale: CGFloat
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(ProductivityTypography.font(style, scale: textScale * scale, weight: weight))
    }
}

extension View {
    func productivityFont(
        _ style: ProductivityFontStyle,
        scale: CGFloat = 1,
        weight: Font.Weight? = nil
    ) -> some View {
        modifier(ProductivityFontModifier(style: style, scale: scale, weight: weight))
    }

    func productivitySupportingTextStyle() -> some View {
        modifier(ProductivitySupportingTextModifier(compact: false))
    }

    func productivitySupportingNoteStyle() -> some View {
        modifier(ProductivitySupportingTextModifier(compact: true))
    }

    func observeProductivityWindowPresentation() -> some View {
        modifier(ProductivityWindowPresentationModifier())
    }
}

struct ProductivityInfoHint: View {
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .productivityFont(.captionMedium)
                .foregroundStyle(ProductivityTheme.textSecondary.opacity(0.9))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(message)
        .accessibilityLabel("More information")
        .accessibilityHint(message)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(message)
                .productivityFont(.caption)
                .foregroundStyle(ProductivityTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .frame(width: 260, alignment: .leading)
                .padding(14)
                .background(ProductivityTheme.elevatedBackground)
        }
    }
}

private struct ThemePalette {
    let backgroundLight: NSColor
    let backgroundDark: NSColor
    let elevatedBackgroundLight: NSColor
    let elevatedBackgroundDark: NSColor
    let subtleBackgroundLight: NSColor
    let subtleBackgroundDark: NSColor
    let borderLight: NSColor
    let borderDark: NSColor
    let textPrimaryLight: NSColor
    let textPrimaryDark: NSColor
    let textSecondaryLight: NSColor
    let textSecondaryDark: NSColor
    let accent: Color
    let accentSecondary: Color
    let accentTertiary: Color
    let glowLight: NSColor
    let glowDark: NSColor
}

private struct ProductivityWindowPresentationModifier: ViewModifier {
    @State private var isFullScreen = false

    func body(content: Content) -> some View {
        content
            .environment(\.productivityIsFullScreen, isFullScreen)
            .background(WindowPresentationObserver(isFullScreen: $isFullScreen))
    }
}

private struct WindowPresentationObserver: NSViewRepresentable {
    @Binding var isFullScreen: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isFullScreen: $isFullScreen)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isFullScreen = $isFullScreen
        context.coordinator.attach(to: nsView)
    }

    final class Coordinator: NSObject {
        var isFullScreen: Binding<Bool>
        private weak var view: NSView?
        private weak var observedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var connectionAttempts = 0
        private let maximumConnectionAttempts = 30

        init(isFullScreen: Binding<Bool>) {
            self.isFullScreen = isFullScreen
        }

        deinit {
            removeObservers()
        }

        func attach(to view: NSView) {
            if self.view !== view {
                connectionAttempts = 0
            }
            self.view = view

            DispatchQueue.main.async { [weak self] in
                self?.connectIfPossible()
            }
        }

        private func connectIfPossible() {
            guard let view else { return }
            guard let window = view.window else {
                guard connectionAttempts < maximumConnectionAttempts else { return }
                connectionAttempts += 1
                DispatchQueue.main.async { [weak self] in
                    self?.connectIfPossible()
                }
                return
            }

            guard observedWindow !== window else {
                updateState(using: window)
                return
            }

            observedWindow = window
            removeObservers()
            configureWindowAppearance(for: window)
            configureCloseButton(for: window)

            let center = NotificationCenter.default
            observers = [
                center.addObserver(
                    forName: NSWindow.didEnterFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    self?.updateState(using: window)
                },
                center.addObserver(
                    forName: NSWindow.didExitFullScreenNotification,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    self?.updateState(using: window)
                },
                center.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] notification in
                    guard let window = notification.object as? NSWindow else { return }
                    self?.updateState(using: window)
                },
            ]

            updateState(using: window)
        }

        private func updateState(using window: NSWindow) {
            configureWindowAppearance(for: window)
            isFullScreen.wrappedValue = window.styleMask.contains(.fullScreen)
        }

        private func configureWindowAppearance(for window: NSWindow) {
            window.titlebarAppearsTransparent = true
            window.backgroundColor = ProductivityTheme.backgroundNSColor
        }

        private func configureCloseButton(for window: NSWindow) {
            guard let closeButton = window.standardWindowButton(.closeButton) else { return }
            closeButton.target = self
            closeButton.action = #selector(hideMainWindow(_:))
        }

        @objc private func hideMainWindow(_ sender: Any?) {
            observedWindow?.orderOut(nil)
        }

        private func removeObservers() {
            let center = NotificationCenter.default
            observers.forEach(center.removeObserver)
            observers.removeAll()
        }
    }
}

private struct ProductivityFontSpecification {
    let size: CGFloat
    let minimumSize: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let monospacedDigits: Bool

    init(
        size: CGFloat,
        minimumSize: CGFloat,
        weight: Font.Weight,
        design: Font.Design = .default,
        monospacedDigits: Bool = false
    ) {
        self.size = size
        self.minimumSize = minimumSize
        self.weight = weight
        self.design = design
        self.monospacedDigits = monospacedDigits
    }
}
