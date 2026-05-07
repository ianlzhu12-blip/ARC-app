import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(UIKit)
enum AppChrome {
    static func apply() {
        let neutral = UIColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 0.86)
        let accent = UIColor(red: 0.45, green: 0.95, blue: 0.78, alpha: 1)
        let text = UIColor(red: 0.94, green: 0.98, blue: 1.0, alpha: 1)
        let muted = UIColor(red: 0.70, green: 0.78, blue: 0.83, alpha: 1)

        let tab = UITabBarAppearance()
        tab.configureWithTransparentBackground()
        tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        tab.backgroundColor = neutral
        tab.stackedLayoutAppearance.selected.iconColor = accent
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accent]
        tab.stackedLayoutAppearance.normal.iconColor = muted
        tab.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: muted]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        nav.backgroundColor = neutral
        nav.largeTitleTextAttributes = [
            .foregroundColor: text,
            .font: UIFont.systemFont(ofSize: 34, weight: .bold)
        ]
        nav.titleTextAttributes = [
            .foregroundColor: text,
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = accent.withAlphaComponent(0.88)
        segmented.setTitleTextAttributes([
            .foregroundColor: UIColor(red: 0.025, green: 0.045, blue: 0.055, alpha: 1),
            .font: UIFont.systemFont(ofSize: 13, weight: .bold)
        ], for: .selected)
        segmented.setTitleTextAttributes([
            .foregroundColor: muted,
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold)
        ], for: .normal)
    }
}
#endif

struct ARCBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.arcNeutral,
                    Color.arcNeutralSecondary,
                    Color.arcNeutral
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.arcSecondary.opacity(0.58),
                    .clear,
                    Color.arcCyan.opacity(0.14)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            TechGridOverlay()
                .opacity(0.58)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.055), .clear, .black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .ignoresSafeArea()
    }
}

private struct TechGridOverlay: View {
    var body: some View {
        Canvas { context, size in
            var grid = Path()
            let spacing: CGFloat = 34
            for x in stride(from: CGFloat(0), through: size.width, by: spacing) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: CGFloat(0), through: size.height, by: spacing) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(Color.arcMint.opacity(0.045)), lineWidth: 0.6)

            var horizon = Path()
            for y in stride(from: CGFloat(42), through: size.height, by: 136) {
                horizon.move(to: CGPoint(x: 0, y: y))
                horizon.addLine(to: CGPoint(x: size.width, y: max(0, y - 42)))
            }
            context.stroke(horizon, with: .color(Color.arcCyan.opacity(0.055)), lineWidth: 1)
        }
        .blendMode(.screen)
        .allowsHitTesting(false)
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.arcMint)
                    .frame(width: 5, height: 18)
                Text(title)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.arcSubtext)
                    .textCase(.uppercase)
                    .tracking(1.1)
            }
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.black).monospacedDigit())
                .foregroundStyle(Color.arcText)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.arcSubtext)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

struct NumberField: View {
    var title: String
    @Binding var value: Double
    var suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.arcSubtext)
            HStack {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Text(suffix)
                    .foregroundStyle(Color.arcSubtext)
            }
            .fieldStyle()
        }
    }
}

struct OptionalNumberField: View {
    var title: String
    @Binding var value: Double?
    var suffix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.arcSubtext)
            HStack {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Text(suffix)
                    .foregroundStyle(Color.arcSubtext)
            }
            .fieldStyle()
        }
    }
}

struct MotorSelectionField: View {
    var title: String = "Motor"
    @Binding var selection: String
    var motors: [MotorSpec]

    private var suggestions: [MotorSpec] {
        let query = selection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty {
            return Array(motors.prefix(6))
        }
        return Array(
            motors.lazy.filter {
                $0.designation.lowercased().contains(query) ||
                $0.manufacturer.lowercased().contains(query)
            }
            .prefix(8)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.arcSubtext)
            TextField("Example: F24W-4,7", text: $selection)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .fieldStyle()
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions) { motor in
                            Button {
                                selection = motor.designation
                            } label: {
                                Text(motor.designation)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(selection == motor.designation ? Color.arcInk : Color.arcText)
                            .background(selection == motor.designation ? Color.arcMint : Color.arcGlassField, in: Capsule())
                            .overlay(Capsule().stroke(selection == motor.designation ? Color.arcMint : Color.arcStroke))
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .foregroundStyle(Color.arcText)
            .background(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.105),
                        Color.arcGlassFill,
                        Color.black.opacity(0.105)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.30),
                                Color.arcMint.opacity(0.20),
                                Color.arcCyan.opacity(0.10),
                                Color.white.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
            .shadow(color: Color.arcMint.opacity(0.055), radius: 18, x: 0, y: 0)
    }

    func fieldStyle() -> some View {
        self
            .font(.system(.body, design: .rounded).weight(.semibold))
            .foregroundStyle(Color.arcText)
            .tint(Color.arcMint)
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color.arcGlassField, Color.black.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.arcStroke))
    }

    func innerPanelStyle(cornerRadius: CGFloat = 18) -> some View {
        self
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.080), Color.arcSecondary.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.arcStroke)
            )
    }
}

extension Color {
    static let arcNeutral = Color(red: 0.035, green: 0.052, blue: 0.080)
    static let arcNeutralSecondary = Color(red: 0.070, green: 0.115, blue: 0.165)
    static let arcSecondary = Color(red: 0.105, green: 0.205, blue: 0.285)
    static let arcMint = Color(red: 0.45, green: 0.95, blue: 0.78)
    static let arcCyan = Color(red: 0.34, green: 0.76, blue: 1.0)
    static let arcAmber = Color(red: 1.0, green: 0.82, blue: 0.38)
    static let arcOrange = Color(red: 1.0, green: 0.48, blue: 0.34)
    static let arcText = Color(red: 0.94, green: 0.98, blue: 1.0)
    static let arcSubtext = Color(red: 0.70, green: 0.78, blue: 0.83)
    static let arcInk = Color(red: 0.025, green: 0.045, blue: 0.055)
    static let arcGlassFill = Color(red: 0.10, green: 0.16, blue: 0.22).opacity(0.66)
    static let arcGlassField = Color(red: 0.14, green: 0.22, blue: 0.30).opacity(0.68)
    static let arcStroke = Color.white.opacity(0.18)
}
