import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var newChecklistItem = ""
    @State private var isEditingChecklist = false

    private var averageAltitude: Double {
        store.flights.isEmpty ? 0 : store.flights.map(\.measuredAltitudeFeet).reduce(0, +) / Double(store.flights.count)
    }

    private var bestFlight: Flight? {
        if store.isCompetitionMode {
            return store.bestScoredFlights(limit: 1).first
        }
        return store.flights.min {
            altitudeMiss(for: $0) < altitudeMiss(for: $1)
        }
    }

    private var spread: Double {
        guard let minAltitude = store.flights.map(\.measuredAltitudeFeet).min(),
              let maxAltitude = store.flights.map(\.measuredAltitudeFeet).max()
        else { return 0 }
        return maxAltitude - minAltitude
    }

    private var bestTwo: [Flight] {
        if store.isCompetitionMode {
            return store.bestScoredFlights(limit: 2)
        }
        return store.flights
            .sorted { altitudeMiss(for: $0) < altitudeMiss(for: $1) }
            .prefix(2)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    if store.flightMode == .competition {
                        competitionRulesCard
                        competitionCard
                    }
                    if store.flightMode == .nationals {
                        competitionRulesCard
                        nationalsCard
                    }
                    launchChecklistCard
                    statsGrid
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
        VStack(alignment: .leading, spacing: 14) {
            Text("American Rocketry Challenge")
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.arcAmber)
                .textCase(.uppercase)
                .tracking(2)
            Text("RocketTune")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .kerning(-2)
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
            .padding()
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            HStack {
                Text(store.isCompetitionMode ? "Target" : "Reference")
                Spacer()
                TextField("800", value: $store.targetAltitudeFeet, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onSubmit { store.save() }
                Text("ft")
            }
            .padding()
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(22)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 30))
        .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.12)))
    }

    private var competitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Competition Mode", systemImage: "target")
                .font(.headline)
            Text("Practice against the target altitude and watch your best two target matches.")
                .foregroundStyle(.secondary)
            ForEach(bestTwo) { flight in
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

    private var nationalsCard: some View {
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
                    updateLaunchTimerLiveActivity()
                } label: {
                    Label("Restart", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text("Best two qualifying flights")
                .font(.headline)
            ForEach(bestTwo) { flight in
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
                .padding(10)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
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

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatTile(title: "Average", value: "\(Int(averageAltitude)) ft", subtitle: "\(store.flights.count) flights")
            StatTile(
                title: "Best Match",
                value: bestFlight.map { "\(Int($0.measuredAltitudeFeet)) ft" } ?? "None",
                subtitle: bestFlight.map {
                    let summary = store.scoreSummary(for: $0)
                    if summary.isDisqualified {
                        return "disqualified"
                    }
                    return summary.totalPoints.map { "\($0) points" } ?? "\(Int(altitudeMiss(for: $0))) ft off"
                } ?? "Log a flight"
            )
            StatTile(title: "Spread", value: "\(Int(spread)) ft", subtitle: "lower is steadier")
            StatTile(title: "Rockets", value: "\(store.rockets.count)", subtitle: "\(store.teams.count) teams")
        }
    }

    private var recentFlights: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Flights")
                .font(.title3.bold())
            ForEach(store.flights.prefix(6)) { flight in
                let summary = store.scoreSummary(for: flight)
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(Int(flight.measuredAltitudeFeet)) ft")
                            .font(.headline)
                        Text(flight.flownAt, style: .date)
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
                    if store.isCompetitionMode || (flight.round ?? "") != FlightMode.hobby.shortTitle {
                        if summary.isDisqualified {
                            Text("Disqualified")
                                .foregroundStyle(Color.arcOrange)
                        } else if let totalPoints = summary.totalPoints {
                            Text("\(totalPoints) points")
                                .foregroundStyle(Color.arcAmber)
                        }
                    } else {
                        Text("\(Int(altitudeMiss(for: flight))) ft off")
                            .foregroundStyle(Color.arcAmber)
                    }
                }
                .padding()
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
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
