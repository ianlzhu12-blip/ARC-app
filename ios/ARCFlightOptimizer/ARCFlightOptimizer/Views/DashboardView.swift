import SwiftUI

private struct DashboardStats {
    var averageAltitude: Double
    var spread: Double
    var bestFlight: Flight?
    var bestTwo: [Flight]
}

struct DashboardView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var newChecklistItem = ""
    @State private var isEditingChecklist = false

    private func makeDashboardStats() -> DashboardStats {
        let flights = store.flights
        let averageAltitude: Double
        let spread: Double

        if flights.isEmpty {
            averageAltitude = 0
            spread = 0
        } else {
            var altitudeTotal = 0.0
            var minAltitude = Double.greatestFiniteMagnitude
            var maxAltitude = -Double.greatestFiniteMagnitude

            for flight in flights {
                let altitude = flight.measuredAltitudeFeet
                altitudeTotal += altitude
                minAltitude = min(minAltitude, altitude)
                maxAltitude = max(maxAltitude, altitude)
            }

            averageAltitude = altitudeTotal / Double(flights.count)
            spread = maxAltitude - minAltitude
        }

        let bestTwo: [Flight]
        if store.isCompetitionMode {
            bestTwo = store.bestScoredFlights(limit: 2)
        } else {
            bestTwo = Array(
                flights
                    .sorted { altitudeMiss(for: $0) < altitudeMiss(for: $1) }
                    .prefix(2)
            )
        }

        return DashboardStats(
            averageAltitude: averageAltitude,
            spread: spread,
            bestFlight: bestTwo.first,
            bestTwo: bestTwo
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    let stats = makeDashboardStats()
                    hero
                    if store.flightMode == .competition {
                        competitionRulesCard
                        competitionCard(stats: stats)
                    }
                    if store.flightMode == .nationals {
                        competitionRulesCard
                        nationalsCard(stats: stats)
                    }
                    launchChecklistCard
                    statsGrid(stats: stats)
                    latestFlightReview
                    recentFlights
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .scrollIndicators(.visible)
            .navigationTitle("RocketTune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                store.syncLaunchWindowRemaining()
                updateLaunchTimerLiveActivity()
            }
            .task {
                await store.refreshCompetitionInfoIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var latestFlightReview: some View {
        if let flight = store.flights.first {
            let analysis = VideoFlightAnalyzer.diagnoseFlight(
                flight: flight,
                rocket: store.rocket(for: flight),
                targetAltitudeFeet: reviewTargetAltitude(for: flight),
                targetFlightTimeRange: reviewTimeRange(for: flight)
            )
            VStack(alignment: .leading, spacing: 10) {
                Label("Latest Flight Review", systemImage: "waveform.and.magnifyingglass")
                    .font(.title3.bold())
                Text(analysis.title)
                    .font(.headline)
                    .foregroundStyle(reviewColor(analysis.severityColorName))
                Text(analysis.summary)
                    .foregroundStyle(.secondary)
                ForEach(analysis.evidence.prefix(3), id: \.self) { evidence in
                    Text("Evidence: \(evidence)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(analysis.recommendations.prefix(2), id: \.self) { recommendation in
                    Text("Next: \(recommendation)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.arcMint)
                }
            }
            .cardStyle()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("American Rocketry Challenge")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Color.arcAmber)
                    .textCase(.uppercase)
                    .tracking(2)
                Spacer()
                Label("Flight OS", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.arcMint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.arcMint.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(Color.arcMint.opacity(0.28)))
            }
            Text("RocketTune")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .kerning(-2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.arcText, Color.arcMint.opacity(0.92)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Picker("Mode", selection: Binding(
                get: { store.flightMode },
                set: { store.setFlightMode($0) }
            )) {
                ForEach(store.selectableFlightModes) { mode in
                    Text(mode.shortTitle).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            if !store.hasNationalsAccess {
                Label("Nationals unlocks after Account confirms your team made Nationals.", systemImage: "lock.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcAmber)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(store.flightMode.shortTitle)
                    .font(.headline)
                Text(store.flightMode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .innerPanelStyle()
            HStack {
                Label(store.isCompetitionMode ? "Target" : "Reference", systemImage: "scope")
                    .font(.headline)
                Spacer()
                TextField("800", value: Binding(
                    get: { store.targetAltitudeFeet },
                    set: { store.updateTargetAltitude($0) }
                ), format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text("ft")
                    .foregroundStyle(Color.arcSubtext)
            }
            .innerPanelStyle()
        }
        .cardStyle()
    }

    private func competitionCard(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Competition Mode", systemImage: "target")
                .font(.headline)
            Text("Practice against the target altitude and watch your best two target matches.")
                .foregroundStyle(.secondary)
            ForEach(stats.bestTwo) { flight in
                let summary = store.scoreSummary(for: flight)
                HStack {
                    Text("\(Int(flight.measuredAltitudeFeet)) ft")
                    Spacer()
                    if summary.isDisqualified {
                        Text("Disqualified")
                            .foregroundStyle(Color.arcOrange)
                    } else if let totalPoints = summary.totalPoints {
                        Text("\(totalPoints) points")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var competitionRulesCard: some View {
        let info = store.syncedCompetitionInfo
        let season = String(info.seasonYear)
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(verbatim: "ARC \(season) Snapshot")
                    .font(.headline)
            } icon: {
                Image(systemName: "doc.text.fill")
            }
            Text("Altitude target: \(Int(info.altitudeGoalFeet)) ft")
            Text("Flight time target: \(Int(info.flightTimeRange.lowerBound))-\(Int(info.flightTimeRange.upperBound)) s")
            Text("Max lift-off mass: \(Int(info.maxLiftOffMassGrams)) g")
            Text("Minimum length: \(Int(info.minimumLengthMillimeters)) mm")
            Text("Minimum body diameter: \(Int(info.minimumBodyDiameterMillimeters)) mm")
            Text("Qualification window: \(info.qualificationWindow.arcPlainText)")
            Text("National Finals: \(info.finalsDate.arcPlainText), \(info.finalsLocation.arcPlainText)")
            Text("Competition motors are loaded from the official ARC approved motors list for the synced season.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func nationalsCard(stats: DashboardStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = store.launchWindowRemaining(at: context.date)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Launch window", systemImage: timerIcon)
                        Spacer()
                        Text(store.launchTimerState.displayName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(timerStatusColor)
                    }
                    Text(timeString(remaining))
                        .font(.system(size: 44, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.arcAmber)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Live Activity updates the Lock Screen and Dynamic Island on supported iPhones while the timer is running.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Button {
                    if store.launchTimerState == .running {
                        store.pauseLaunchWindow()
                    } else {
                        store.startLaunchWindow()
                    }
                    updateLaunchTimerLiveActivity()
                } label: {
                    Label(store.launchTimerState == .running ? "Pause" : "Start", systemImage: store.launchTimerState == .running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.restartLaunchWindow()
                    endLaunchTimerLiveActivity()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("Best two qualifying flights")
                .font(.headline)
            ForEach(stats.bestTwo) { flight in
                let summary = store.scoreSummary(for: flight)
                HStack {
                    Text("\(Int(flight.measuredAltitudeFeet)) ft")
                    Spacer()
                    if summary.isDisqualified {
                        Text("Disqualified")
                            .foregroundStyle(Color.arcOrange)
                    } else if let totalPoints = summary.totalPoints {
                        Text("\(totalPoints) points")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var timerIcon: String {
        switch store.launchTimerState {
        case .running: return "timer"
        case .paused: return "pause.circle.fill"
        case .stopped: return "timer.circle"
        }
    }

    private var timerStatusColor: Color {
        switch store.launchTimerState {
        case .running: return Color.arcMint
        case .paused: return Color.arcAmber
        case .stopped: return .secondary
        }
    }

    private var launchChecklistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Launch Checklist", systemImage: "checklist")
                    .font(.title3.bold())
                Spacer()
                Button(isEditingChecklist ? "Done" : "Edit") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isEditingChecklist.toggle()
                    }
                }
                .buttonStyle(.bordered)
            }
            Text(isEditingChecklist ? "Add, rename, or remove checklist items for your team." : "Tap items as you finish launch prep.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(store.launchChecklistItems) { item in
                HStack(spacing: 10) {
                    Button {
                        store.toggleLaunchChecklistItem(id: item.id)
                    } label: {
                        Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(item.isComplete ? Color.arcMint : .secondary)
                    }
                    .buttonStyle(.plain)

                    if isEditingChecklist {
                        TextField(
                            "Checklist item",
                            text: Binding(
                                get: { item.title },
                                set: { store.updateLaunchChecklistItem(id: item.id, title: $0) }
                            )
                        )
                        .textInputAutocapitalization(.sentences)
                        .strikethrough(item.isComplete)
                        .foregroundStyle(item.isComplete ? .secondary : .primary)

                        Button(role: .destructive) {
                            store.deleteLaunchChecklistItem(id: item.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    } else {
                        Text(item.title)
                            .strikethrough(item.isComplete)
                            .foregroundStyle(item.isComplete ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .innerPanelStyle(cornerRadius: 14)
            }

            if isEditingChecklist {
                HStack {
                    TextField("Add checklist item", text: $newChecklistItem)
                        .textInputAutocapitalization(.sentences)
                        .fieldStyle()
                        .onSubmit(addChecklistItem)
                    Button {
                        addChecklistItem()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    .disabled(newChecklistItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .cardStyle()
    }

    private func statsGrid(stats: DashboardStats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Average", value: "\(Int(stats.averageAltitude)) ft", subtitle: "\(store.flights.count) flights")
            StatTile(
                title: "Best Match",
                value: stats.bestFlight.map { "\(Int($0.measuredAltitudeFeet)) ft" } ?? "None",
                subtitle: stats.bestFlight.map {
                    let summary = store.scoreSummary(for: $0)
                    if summary.isDisqualified {
                        return "disqualified"
                    }
                    return summary.totalPoints.map { "\($0) points" } ?? "\(Int(altitudeMiss(for: $0))) ft off"
                } ?? "Log a flight"
            )
            StatTile(title: "Spread", value: "\(Int(stats.spread)) ft", subtitle: "lower is steadier")
            StatTile(title: "Rockets", value: "\(store.rockets.count)", subtitle: "\(store.teams.count) teams")
        }
    }

    private var recentFlights: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Flights")
                    .font(.title3.bold())
                Spacer()
                if !store.flights.isEmpty {
                    NavigationLink {
                        AllFlightsView()
                    } label: {
                        Text("View All")
                            .font(.footnote.weight(.bold))
                    }
                }
            }
            ForEach(store.flights.prefix(6)) { flight in
                DashboardFlightRow(flight: flight)
            }
        }
        .cardStyle()
    }

    private func timeString(_ seconds: Int) -> String {
        "\(String(format: "%02d", seconds / 60)):\(String(format: "%02d", seconds % 60))"
    }

    private func updateLaunchTimerLiveActivity() {
        LaunchTimerLiveActivity.update(
            state: store.launchTimerState,
            remainingSeconds: store.launchWindowRemaining(),
            endsAt: store.launchWindowEndsAt
        )
    }

    private func endLaunchTimerLiveActivity() {
        LaunchTimerLiveActivity.end(
            state: store.launchTimerState,
            remainingSeconds: store.launchWindowRemaining()
        )
    }

    private func addChecklistItem() {
        store.addLaunchChecklistItem(newChecklistItem)
        newChecklistItem = ""
    }

    private func altitudeMiss(for flight: Flight) -> Double {
        abs(flight.measuredAltitudeFeet - store.scoringTargetAltitude(for: flight))
    }

    private func reviewTargetAltitude(for flight: Flight) -> Double {
        if (flight.round ?? "") == FlightMode.hobby.shortTitle {
            return flight.targetAltitudeFeet ?? store.targetAltitudeFeet
        }
        return store.scoringTargetAltitude(for: flight)
    }

    private func reviewTimeRange(for flight: Flight) -> ClosedRange<Double>? {
        (flight.round ?? "") == FlightMode.hobby.shortTitle ? nil : store.syncedCompetitionInfo.flightTimeRange
    }

    private func reviewColor(_ name: String) -> Color {
        switch name {
        case "mint":
            return Color.arcMint
        case "orange":
            return Color.arcOrange
        default:
            return Color.arcAmber
        }
    }
}

private struct AllFlightsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var searchText = ""
    @State private var editingFlight: Flight?
    @State private var expandedFlightID: UUID?

    private func filteredFlights(rocketNamesByID: [UUID: String]) -> [Flight] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return store.flights }
        let query = trimmed.lowercased()
        return store.flights.filter { flight in
            let rocketName = rocketNamesByID[flight.rocketID]?.lowercased() ?? ""
            return rocketName.contains(query) ||
                flight.motorDesignation.lowercased().contains(query) ||
                flight.notes.lowercased().contains(query) ||
                flight.eggStatus.displayName.lowercased().contains(query)
        }
    }

    var body: some View {
        let rocketNamesByID = Dictionary(uniqueKeysWithValues: store.rockets.map { ($0.id, $0.name) })
        let visibleFlights = filteredFlights(rocketNamesByID: rocketNamesByID)

        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("Every manual and spreadsheet-imported flight is shown here. Imported rows stay editable from the Log screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .cardStyle()

                ForEach(visibleFlights) { flight in
                    VStack(alignment: .leading, spacing: 10) {
                        DashboardFlightRow(flight: flight, rocketName: rocketNamesByID[flight.rocketID])
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    expandedFlightID = expandedFlightID == flight.id ? nil : flight.id
                                }
                            }
                        if expandedFlightID == flight.id {
                            DashboardFlightAnalysisCard(flight: flight)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        HStack {
                            Button {
                                editingFlight = flight
                            } label: {
                                Label("Edit", systemImage: "square.and.pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button(expandedFlightID == flight.id ? "Hide Summary" : "Summary") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    expandedFlightID = expandedFlightID == flight.id ? nil : flight.id
                                }
                            }
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                flight.attachments.forEach(VideoFlightAnalyzer.deleteStoredVideo)
                                store.deleteFlight(id: flight.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .padding(.bottom, 28)
        }
        .background {
            ARCBackground()
                .allowsHitTesting(false)
        }
        .navigationTitle("All Flights")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Rocket, motor, notes, egg")
        .sheet(item: $editingFlight) { flight in
            FlightEditSheet(flight: flight)
        }
    }
}

private struct DashboardFlightAnalysisCard: View {
    @EnvironmentObject private var store: FlightStore
    let flight: Flight

    var body: some View {
        let analysis = VideoFlightAnalyzer.diagnoseFlight(
            flight: flight,
            rocket: store.rocket(for: flight),
            targetAltitudeFeet: targetAltitude,
            targetFlightTimeRange: timeRange
        )
        VStack(alignment: .leading, spacing: 6) {
            Label(analysis.title, systemImage: "waveform.and.magnifyingglass")
                .font(.caption.weight(.bold))
                .foregroundStyle(color(analysis.severityColorName))
            Text(analysis.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(analysis.recommendations.prefix(2), id: \.self) { item in
                Text("Improve: \(item)")
                    .font(.caption2)
                    .foregroundStyle(Color.arcMint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color(analysis.severityColorName).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color(analysis.severityColorName).opacity(0.35)))
    }

    private var targetAltitude: Double {
        if (flight.round ?? "") == FlightMode.hobby.shortTitle {
            return flight.targetAltitudeFeet ?? store.targetAltitudeFeet
        }
        return store.scoringTargetAltitude(for: flight)
    }

    private var timeRange: ClosedRange<Double>? {
        (flight.round ?? "") == FlightMode.hobby.shortTitle ? nil : store.syncedCompetitionInfo.flightTimeRange
    }

    private func color(_ name: String) -> Color {
        switch name {
        case "mint":
            return Color.arcMint
        case "orange":
            return Color.arcOrange
        default:
            return Color.arcAmber
        }
    }
}

private struct FlightEditSheet: View {
    @EnvironmentObject private var store: FlightStore
    @Environment(\.dismiss) private var dismiss
    let flight: Flight

    @State private var selectedRocketID: UUID?
    @State private var motorDesignation: String
    @State private var mass: Double?
    @State private var targetAltitude: Double?
    @State private var altitude: Double?
    @State private var flightTimeSeconds: Double?
    @State private var temperature: Double?
    @State private var wind: Double?
    @State private var humidity: Double?
    @State private var location: String
    @State private var parachute: Double?
    @State private var reefedCentimeters: Double?
    @State private var descentSystem: String
    @State private var eggStatus: EggStatus
    @State private var notes: String

    init(flight: Flight) {
        self.flight = flight
        _selectedRocketID = State(initialValue: flight.rocketID)
        _motorDesignation = State(initialValue: flight.motorDesignation)
        _mass = State(initialValue: flight.rocketMassGrams)
        _targetAltitude = State(initialValue: flight.targetAltitudeFeet)
        _altitude = State(initialValue: flight.measuredAltitudeFeet)
        _flightTimeSeconds = State(initialValue: flight.flightTimeSeconds)
        _temperature = State(initialValue: flight.weather.temperatureF)
        _wind = State(initialValue: flight.weather.windMPH)
        _humidity = State(initialValue: flight.weather.humidityPercent)
        _location = State(initialValue: flight.weather.location)
        _parachute = State(initialValue: flight.parachuteSizeInches)
        _reefedCentimeters = State(initialValue: flight.parachuteReefedCentimeters)
        _descentSystem = State(initialValue: flight.descentSystem)
        _eggStatus = State(initialValue: flight.eggStatus)
        _notes = State(initialValue: FlightNoteCleaner.editableNotes(from: flight.notes))
    }

    private var selectedRocket: Rocket? {
        if let selectedRocketID,
           let rocket = store.rockets.first(where: { $0.id == selectedRocketID }) {
            return rocket
        }
        return store.rocket(for: flight) ?? store.rockets.first
    }

    private var canSave: Bool {
        selectedRocket != nil && mass != nil && altitude != nil && parachute != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Rocket", selection: $selectedRocketID) {
                        ForEach(store.rockets) { rocket in
                            Text(rocket.name).tag(Optional(rocket.id))
                        }
                    }
                    .pickerStyle(.menu)

                    MotorSelectionField(selection: $motorDesignation, motors: MotorCatalog.motors(for: store.flightMode))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(EggStatus.allCases) { status in
                            Button {
                                eggStatus = status
                            } label: {
                                Text(status.displayName)
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(eggStatus == status ? .black : .primary)
                            .background(eggStatus == status ? Color.arcMint : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    OptionalNumberField(title: "Rocket Mass", value: $mass, suffix: "g")
                    OptionalNumberField(title: "Wanted Altitude", value: $targetAltitude, suffix: "ft")
                    OptionalNumberField(title: "Measured Altitude", value: $altitude, suffix: "ft")
                    OptionalNumberField(title: "Flight Time", value: $flightTimeSeconds, suffix: "s")
                    HStack {
                        OptionalNumberField(title: "Temp", value: $temperature, suffix: "F")
                        OptionalNumberField(title: "Wind", value: $wind, suffix: "mph")
                    }
                    HStack {
                        OptionalNumberField(title: "Humidity", value: $humidity, suffix: "%")
                        OptionalNumberField(title: "Chute", value: $parachute, suffix: "in")
                    }
                    OptionalNumberField(title: "Reefed Length", value: $reefedCentimeters, suffix: "cm")
                    TextField("Location", text: $location)
                        .fieldStyle()
                    TextField("Descent system", text: $descentSystem)
                        .fieldStyle()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .fieldStyle()

                    Button {
                        save()
                    } label: {
                        Label("Update Flight", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }
                .padding()
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .navigationTitle("Edit Flight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func save() {
        guard let rocket = selectedRocket,
              let mass,
              let altitude,
              let parachute else { return }
        store.updateFlight(
            id: flight.id,
            rocket: rocket,
            motorDesignation: motorDesignation,
            mass: mass,
            weather: Weather(temperatureF: temperature ?? 0, windMPH: wind ?? 0, humidityPercent: humidity ?? 0, location: location),
            altitude: altitude,
            targetAltitude: targetAltitude,
            flightTimeSeconds: flightTimeSeconds,
            parachute: parachute,
            reefedCentimeters: reefedCentimeters,
            descentSystem: descentSystem,
            eggStatus: eggStatus,
            notes: notes,
            attachments: flight.attachments,
            round: flight.round
        )
        dismiss()
    }
}

private struct DashboardFlightRow: View {
    @EnvironmentObject private var store: FlightStore
    let flight: Flight
    var rocketName: String? = nil

    var body: some View {
        let summary = store.scoreSummary(for: flight)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(flight.measuredAltitudeFeet)) ft")
                    .font(.headline)
                Text(rowSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let flightTimeSeconds = flight.flightTimeSeconds {
                    Text("\(String(format: "%.1f", flightTimeSeconds)) s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Egg: \(flight.eggStatus.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if summary.isDisqualified {
                    Text("Disqualified: \(summary.disqualificationReasons.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.arcOrange)
                }
            }
            Spacer()
            scoreLabel(summary)
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
    }

    private var rowSubtitle: String {
        let displayRocketName = rocketName ?? store.rocket(for: flight)?.name ?? "Unknown Rocket"
        return "\(displayRocketName) • \(flight.motorDesignation) • \(formattedGrams(flight.rocketMassGrams)) • \(flight.flownAt.formatted(date: .abbreviated, time: .shortened))"
    }

    @ViewBuilder
    private func scoreLabel(_ summary: FlightScoreSummary) -> some View {
        if store.isCompetitionMode || (flight.round ?? "") != FlightMode.hobby.shortTitle {
            if summary.isDisqualified {
                Text("Disqualified")
                    .foregroundStyle(Color.arcOrange)
            } else if let totalPoints = summary.totalPoints {
                Text("\(totalPoints) points")
                    .foregroundStyle(Color.arcAmber)
            }
        } else {
            Text("\(Int(abs(flight.measuredAltitudeFeet - store.scoringTargetAltitude(for: flight)))) ft off")
                .foregroundStyle(Color.arcAmber)
        }
    }

    private func formattedGrams(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))g"
        }
        return "\(String(format: "%.1f", value))g"
    }
}
