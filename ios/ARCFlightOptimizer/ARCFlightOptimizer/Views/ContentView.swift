import SwiftUI
import Charts

struct ContentView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var selectedTab = 0

    var body: some View {
        Group {
            if store.needsInitialSetup {
                StartSetupView {
                    selectedTab = 4
                }
            } else {
                TabView(selection: $selectedTab) {
                    DeferredTabContent(tag: 0, selection: $selectedTab) {
                        DashboardView()
                    }
                        .tabItem {
                            Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent")
                        }
                        .tag(0)

                    DeferredTabContent(tag: 1, selection: $selectedTab) {
                        QuickLogView()
                    }
                        .tabItem {
                            Label("Log", systemImage: "plus.circle.fill")
                        }
                        .tag(1)

                    DeferredTabContent(tag: 2, selection: $selectedTab) {
                        InsightsView()
                    }
                        .tabItem {
                            Label("Insights", systemImage: "chart.xyaxis.line")
                        }
                        .tag(2)

                    DeferredTabContent(tag: 3, selection: $selectedTab) {
                        RocketsView()
                    }
                        .tabItem {
                            Label("Rockets", systemImage: "paperplane.fill")
                        }
                        .tag(3)

                    DeferredTabContent(tag: 4, selection: $selectedTab) {
                        AccountView()
                    }
                        .tabItem {
                            Label("Account", systemImage: "person.crop.circle")
                        }
                        .tag(4)
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color.arcMint)
    }
}

private struct StartSetupView: View {
    @EnvironmentObject private var store: FlightStore
    var onComplete: () -> Void

    @State private var step = 0
    @State private var selectedMode: FlightMode = .hobby
    @State private var teamName = ""
    @State private var school = ""
    @State private var rocketName = ""
    @State private var dryMass = 650.0
    @State private var diameter = 66.0
    @State private var material: RocketMaterial = .cardboard
    @State private var parachuteSize = 18.0
    @State private var defaultMotorDesignation = "F24W-4,7"
    @State private var heightMillimeters = 700.0
    @State private var widthMillimeters = 66.0
    @State private var cachedMotors: [MotorSpec] = []

    private var availableMotors: [MotorSpec] {
        cachedMotors.isEmpty ? MotorCatalog.motors(for: selectedMode) : cachedMotors
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Choose Mode"
        case 1: return "Team Setup"
        default: return "First Rocket"
        }
    }

    private var stepSubtitle: String {
        switch step {
        case 0: return "Pick how you want the app to score, target, and tune flights."
        case 1: return "Required so flights can be grouped by team and shown correctly in Account."
        default: return "Required so the AI has a real rocket to calculate from."
        }
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            return true
        case 1:
            return !teamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return !rocketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                dryMass > 0 &&
                diameter > 0 &&
                heightMillimeters > 0 &&
                widthMillimeters > 0 &&
                parachuteSize > 0 &&
                !defaultMotorDesignation.isEmpty
        }
    }

    private var validationMessage: String? {
        guard !canContinue else { return nil }
        switch step {
        case 1:
            return "Team name and school/organization are required."
        case 2:
            return "Rocket name and all rocket measurements must be filled in."
        default:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard
                    progressCard
                    activeSlide
                    navigationButtons
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.visible)
            .navigationBarHidden(true)
            .onAppear {
                refreshMotorsForSelectedMode()
            }
            .onChange(of: selectedMode) { _, _ in
                refreshMotorsForSelectedMode()
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("RocketTune")
                .font(.system(size: 40, weight: .black, design: .rounded))
            Text("A quick setup flow gets you into the app with a clean logbook. No demo flights are loaded.")
                .foregroundStyle(.secondary)
            Text("After setup, you’ll land on Account to register yourself and add teammates.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(stepTitle)
                    .font(.title3.bold())
                Spacer()
                Text("\(step + 1) / 3")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.arcMint)
            }
            ProgressView(value: Double(step + 1), total: 3)
                .tint(Color.arcMint)
            Text(stepSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var activeSlide: some View {
        switch step {
        case 0:
            modeCard
        case 1:
            teamCard
        default:
            rocketCard
        }
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            requiredHeader("Mode")
            Text("This can be changed later from the Dashboard.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Picker("Mode", selection: $selectedMode) {
                ForEach(store.selectableFlightModes) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if !store.hasNationalsAccess {
                Text("Nationals unlocks after Account confirms your team made Nationals.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcAmber)
            }
            Text(selectedMode.detail)
                .foregroundStyle(.secondary)
            if selectedMode == .competition || selectedMode == .nationals {
                Text("\(selectedMode.shortTitle) setup uses the synced ARC target of \(Int(store.syncedCompetitionInfo.altitudeGoalFeet)) ft.")
                    .font(.footnote)
                    .foregroundStyle(Color.arcAmber)
            }
        }
        .cardStyle()
    }

    private var teamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            requiredHeader("Team")
            TextField("Team name", text: $teamName)
                .textInputAutocapitalization(.words)
                .fieldStyle()
            TextField("School / organization", text: $school)
                .textInputAutocapitalization(.words)
                .fieldStyle()
            Text("You can register your personal account and add teammates on the next screen.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            validationText
        }
        .cardStyle()
    }

    private var rocketCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            requiredHeader("First Rocket")
            TextField("Rocket name", text: $rocketName)
                .textInputAutocapitalization(.words)
                .fieldStyle()
            Picker("Material", selection: $material) {
                ForEach(RocketMaterial.allCases) { material in
                    Text(material.displayName).tag(material)
                }
            }
            .pickerStyle(.menu)
            MotorSelectionField(title: "Default Motor", selection: $defaultMotorDesignation, motors: availableMotors)
            NumberField(title: "Dry Mass", value: $dryMass, suffix: "g")
            NumberField(title: "Diameter", value: $diameter, suffix: "mm")
            NumberField(title: "Height", value: $heightMillimeters, suffix: "mm")
            NumberField(title: "Width", value: $widthMillimeters, suffix: "mm")
            NumberField(title: "Parachute", value: $parachuteSize, suffix: "in")
            validationText
        }
        .cardStyle()
    }

    private var navigationButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                Button {
                    advance()
                } label: {
                    Label(step == 2 ? "Finish Setup" : "Next", systemImage: step == 2 ? "checkmark.circle.fill" : "chevron.right")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canContinue)
            }
            if step == 2 {
                Text("Finish Setup opens Account next so you can register and add your team members.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private func requiredHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.title3.bold())
            Text("Required")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.arcOrange.opacity(0.18), in: Capsule())
                .foregroundStyle(Color.arcAmber)
        }
    }

    @ViewBuilder
    private var validationText: some View {
        if let validationMessage {
            Text(validationMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.arcAmber)
        }
    }

    private func advance() {
        guard canContinue else { return }
        if step < 2 {
            step += 1
        } else {
            store.completeInitialSetup(
                mode: selectedMode,
                teamName: teamName,
                school: school,
                rocketName: rocketName,
                dryMass: dryMass,
                diameter: diameter,
                material: material,
                parachuteSize: parachuteSize,
                defaultMotorDesignation: defaultMotorDesignation,
                heightMillimeters: heightMillimeters,
                widthMillimeters: widthMillimeters
            )
            onComplete()
        }
    }

    private func refreshMotorsForSelectedMode() {
        let motors = MotorCatalog.motors(for: selectedMode)
        cachedMotors = motors
        if !motors.contains(where: { $0.designation == defaultMotorDesignation }) {
            defaultMotorDesignation = motors.first?.designation ?? ""
        }
    }
}

private extension StartSetupView {
    init() {
        self.onComplete = {}
    }
}

private struct DeferredTabContent<Content: View>: View {
    let tag: Int
    @Binding var selection: Int
    @ViewBuilder var content: () -> Content
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if hasLoaded || selection == tag {
                content()
            } else {
                Color.clear
            }
        }
        .onAppear {
            loadIfSelected()
        }
        .onChange(of: selection) { _, _ in
            loadIfSelected()
        }
    }

    private func loadIfSelected() {
        guard selection == tag, !hasLoaded else { return }
        hasLoaded = true
    }
}

#Preview {
    ContentView()
        .environmentObject(FlightStore())
}
