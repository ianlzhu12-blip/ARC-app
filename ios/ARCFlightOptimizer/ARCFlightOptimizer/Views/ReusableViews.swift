import SwiftUI

struct ARCBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.07, blue: 0.13), Color(red: 0.06, green: 0.13, blue: 0.22), Color(red: 0.10, green: 0.12, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            HStack {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Text(suffix)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
            HStack {
                TextField(title, value: $value, format: .number)
                    .keyboardType(.decimalPad)
                Text(suffix)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
                            .foregroundStyle(selection == motor.designation ? .black : .primary)
                            .background(selection == motor.designation ? Color.arcMint : .white.opacity(0.08), in: Capsule())
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
            .padding()
            .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(.white.opacity(0.12)))
    }

    func fieldStyle() -> some View {
        self
            .padding(12)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.12)))
    }
}

extension Color {
    static let arcMint = Color(red: 0.16, green: 0.72, blue: 0.58)
    static let arcAmber = Color(red: 1.0, green: 0.81, blue: 0.36)
    static let arcOrange = Color(red: 1.0, green: 0.56, blue: 0.36)
}
