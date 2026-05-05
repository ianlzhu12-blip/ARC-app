import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var selectedRocketID: UUID?
    @State private var predictedMass = 702.0
    @State private var predictedMotorDesignation = "F24W-4,7"
    @State private var predictedTemp = 72.0
    @State private var predictedWind = 6.0
    @State private var predictedHumidity = 45.0
    @State private var nationalsTargetHeight = 750.0
    @State private var nationalsTargetText = "750"
    @State private var hobbyTargetHeight = 800.0
    @State private var hobbyMaxAltitude = false
    @State private var selectedNationalsGraphTarget: Double?
    @State private var nationalsXCenter = 700.0
    @State private var nationalsXSpan = 200.0
    @State private var nationalsYCenter: Double?
    @State private var nationalsYSpan: Double?
    @State private var nationalsDragStartXCenter: Double?
    @State private var nationalsDragStartYCenter: Double?
    @State private var nationalsZoomStartXSpan: Double?
    @State private var nationalsZoomStartYSpan: Double?
    @State private var isAdjustingNationalsSlider = false
    @State private var onlineMotorReloadable: Bool?
    @State private var onlineMotorStatusMessage = "Pulling the official ARC motor list helps confirm whether a motor is RMS."
    @State private var cachedPrediction = Prediction(altitudeFeet: 0, confidence: 0, method: "baseline")
    @State private var cachedOptimization: OptimizationResult?
    @State private var cachedRecommendations: [Recommendation] = []
    @State private var cachedCalibrationMeanError: Double?
    @State private var cachedDataSummary = AIDataSummary.empty
    @State private var isRefreshingInsights = false

    private var availableMotors: [MotorSpec] {
        MotorCatalog.motors(for: store.flightMode)
    }

    private var filteredFlights: [Flight] {
        guard let selectedRocketID else { return store.flights }
        guard store.rockets.contains(where: { $0.id == selectedRocketID }) else { return store.flights }
        return store.flights.filter { $0.rocketID == selectedRocketID }
    }

    private var analysisFlights: [Flight] {
        filteredFlights.isEmpty ? store.flights : filteredFlights
    }

    private var modelFlights: [Flight] {
        Array(analysisFlights.prefix(96))
    }

    private var targetAltitudeForAI: Double {
        switch store.flightMode {
        case .hobby:
            return hobbyTargetHeight
        case .competition:
            return store.targetAltitudeFeet
        case .nationals:
            return nationalsTargetHeight
        }
    }

    private var predictionInput: PredictionInput {
        let rocket = selectedRocketForInsights
        let selectedMotor = MotorCatalog.motor(named: predictedMotorDesignation)
        let weather = baselineWeatherForPrediction
        return PredictionInput(
            motorType: selectedMotor?.motorClass ?? .f,
            motorDesignation: predictedMotorDesignation,
            rocketMassGrams: baselineMassForPrediction,
            temperatureF: weather.temperatureF,
            windMPH: weather.windMPH,
            humidityPercent: weather.humidityPercent,
            rocketMaterial: rocket?.material ?? .cardboard,
            parachuteSizeInches: rocket?.parachuteSizeInches ?? 18,
            rocketHeightMillimeters: rocket?.heightMillimeters ?? 700,
            rocketWidthMillimeters: rocket?.widthMillimeters ?? 66
        )
    }

    private var baselineMassForPrediction: Double {
        if let selectedRocketID,
           let recentFlight = store.flights.first(where: { $0.rocketID == selectedRocketID }) {
            return recentFlight.rocketMassGrams
        }
        if let selectedRocketForInsights {
            return selectedRocketForInsights.dryMassGrams + 90
        }
        return store.flights.first?.rocketMassGrams ?? predictedMass
    }

    private var baselineWeatherForPrediction: Weather {
        if let selectedRocketID,
           let recentFlight = store.flights.first(where: { $0.rocketID == selectedRocketID }) {
            return recentFlight.weather
        }
        return store.flights.first?.weather ?? Weather(
            temperatureF: predictedTemp,
            windMPH: predictedWind,
            humidityPercent: predictedHumidity,
            location: ""
        )
    }

    private var prediction: Prediction {
        cachedPrediction
    }

    private var currentOptimization: OptimizationResult? {
        cachedOptimization
    }

    private var reefingRecommendation: Recommendation? {
        guard store.isCompetitionMode else { return nil }
        let targetRange = store.syncedCompetitionInfo.flightTimeRange
        let rangeText = "\(Int(targetRange.lowerBound))-\(Int(targetRange.upperBound)) s"
        let timedFlights = analysisFlights.filter { $0.flightTimeSeconds != nil }

        if let suggestedReef = currentOptimization?.suggestedReefedCentimeters {
            let latestReef = analysisFlights.first?.parachuteReefedCentimeters
            let deltaText: String
            if let latestReef {
                let delta = suggestedReef - latestReef
                if abs(delta) >= 0.5 {
                    deltaText = delta > 0
                        ? "That is about \(String(format: "%.1f", abs(delta))) cm more reefing than the latest log."
                        : "That is about \(String(format: "%.1f", abs(delta))) cm less reefing than the latest log."
                } else {
                    deltaText = "That is very close to the latest logged reefing setup."
                }
            } else {
                deltaText = "Log the actual reefed length after the next flight so this can keep calibrating."
            }

            return Recommendation(
                title: "Parachute reefing target",
                detail: "To aim for the \(rangeText) flight-time window, try about \(String(format: "%.1f", suggestedReef)) cm reefed. \(deltaText)",
                priority: .medium
            )
        }

        guard timedFlights.count >= 3 else {
            return Recommendation(
                title: "Parachute reefing target",
                detail: "Add at least three logs with flight time and centimeters reefed, then Insights can calculate how much to reef for the \(rangeText) window.",
                priority: .low
            )
        }

        let averageTime = timedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(timedFlights.count)
        if targetRange.contains(averageTime) {
            let reefedValues = timedFlights.compactMap(\.parachuteReefedCentimeters)
            let reefText: String
            if reefedValues.isEmpty {
                reefText = "Keep the current parachute setup, and start logging reefed centimeters to lock in a repeatable number."
            } else {
                let averageReef = reefedValues.reduce(0, +) / Double(reefedValues.count)
                reefText = "Keep reefing near your logged average of \(String(format: "%.1f", averageReef)) cm."
            }
            return Recommendation(
                title: "Parachute timing is close",
                detail: "Your timed flights average \(String(format: "%.1f", averageTime)) s, inside the \(rangeText) window. \(reefText)",
                priority: .low
            )
        }

        return Recommendation(
            title: "Parachute reefing needs calibration",
            detail: "Your timed flights average \(String(format: "%.1f", averageTime)) s. Add reefed centimeters to timed logs so the app can calculate an exact reefing length for the \(rangeText) window.",
            priority: .medium
        )
    }

    private var selectedRocketForInsights: Rocket? {
        if let selectedRocketID,
           let rocket = store.rockets.first(where: { $0.id == selectedRocketID }) {
            return rocket
        }
        return store.activeRocket
    }

    private var selectedMotorForInsights: MotorSpec? {
        MotorCatalog.motor(named: predictedMotorDesignation)
    }

    private var effectiveMotorIsReloadable: Bool {
        onlineMotorReloadable ?? selectedMotorForInsights?.reloadable ?? false
    }

    private var nationalsPlanningRange: ClosedRange<Double> {
        store.nationalsPlanningRange
    }

    private var nationalsDefaultAltitudeRange: ClosedRange<Double> {
        600...800
    }

    private var nationalsVisibleXDomain: ClosedRange<Double> {
        let heights = nationalsLoggedFlights.map { plannerHeight(for: $0) } + [nationalsTargetHeight]
        guard !nationalsLoggedFlights.isEmpty else {
            return nationalsDefaultAltitudeRange
        }
        return paddedDomain(heights, minimumPadding: 20)
    }

    private var nationalsTargetPadding: Double {
        min(max(2, nationalsXSpan * 0.08), nationalsXSpan * 0.35)
    }

    private var nationalsEffectiveYSpan: Double {
        nationalsYSpan ?? max(50, nationalsMassDomain.upperBound - nationalsMassDomain.lowerBound)
    }

    private var nationalsVisibleYDomain: ClosedRange<Double> {
        nationalsMassDomain
    }

    private var nationalsLoggedFlights: [Flight] {
        analysisFlights.filter { flight in
            flight.rocketMassGrams.isFinite &&
            flight.measuredAltitudeFeet.isFinite
        }
    }

    private func plannerHeight(for flight: Flight) -> Double {
        flight.targetAltitudeFeet ?? flight.measuredAltitudeFeet
    }

    private var selectedNationalsFlight: Flight? {
        nationalsLoggedFlights.min {
            abs(plannerHeight(for: $0) - nationalsTargetHeight) <
            abs(plannerHeight(for: $1) - nationalsTargetHeight)
        }
    }

    private var nationalsBestFitPoints: [TrendPoint] {
        bestFitPoints(
            nationalsLoggedFlights.map { (plannerHeight(for: $0), $0.rocketMassGrams) },
            xDomain: nationalsVisibleXDomain
        )
    }

    private var insightsCalculationKey: String {
        let flightSignature = modelFlights.map {
            "\($0.id.uuidString.prefix(6)):\(Int($0.rocketMassGrams)):\(Int($0.measuredAltitudeFeet)):\($0.motorDesignation)"
        }.joined(separator: "|")
        return [
            store.flightMode.rawValue,
            selectedRocketID?.uuidString ?? "all",
            predictedMotorDesignation,
            String(Int(targetAltitudeForAI.rounded())),
            String(store.aiLearningRevision),
            String(Int(baselineMassForPrediction.rounded())),
            String(Int(baselineWeatherForPrediction.temperatureF.rounded())),
            String(Int(baselineWeatherForPrediction.windMPH.rounded())),
            String(Int(baselineWeatherForPrediction.humidityPercent.rounded())),
            String(effectiveMotorIsReloadable),
            String(hobbyMaxAltitude),
            String(isAdjustingNationalsSlider),
            flightSignature
        ].joined(separator: "::")
    }

    private var nationalsMassDomain: ClosedRange<Double> {
        guard
            let minMass = nationalsLoggedFlights.map(\.rocketMassGrams).min(),
            let maxMass = nationalsLoggedFlights.map(\.rocketMassGrams).max()
        else {
            return 0...1
        }
        let padding = max(12, (maxMass - minMass) * 0.35)
        return (minMass - padding)...(maxMass + padding)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    predictionCard
                    dataSummaryCard
                    todayConditionsCard
                    calibrationCard
                    recommendationCard
                    if store.isNationalsMode {
                        nationalsPlannerCard
                    }
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollDisabled(isAdjustingNationalsSlider)
            .scrollIndicators(.visible)
            .navigationTitle("Insights")
            .onAppear {
                normalizeInsightsSelections()
                predictedMass = store.activeRocket.map { $0.dryMassGrams + 90 } ?? predictedMass
                nationalsTargetHeight = min(max(store.syncedCompetitionInfo.altitudeGoalFeet, nationalsDefaultAltitudeRange.lowerBound), nationalsDefaultAltitudeRange.upperBound)
                nationalsTargetText = String(Int(nationalsTargetHeight))
                hobbyTargetHeight = store.targetAltitudeFeet
            }
            .onChange(of: store.flightMode) { _, _ in
                normalizeInsightsSelections()
            }
            .onChange(of: store.rockets) { _, _ in
                normalizeInsightsSelections()
            }
            .onChange(of: store.syncedCompetitionInfo) { _, info in
                if store.flightMode == .nationals {
                    nationalsTargetHeight = min(max(nationalsTargetHeight, nationalsDefaultAltitudeRange.lowerBound), nationalsDefaultAltitudeRange.upperBound)
                    if abs(nationalsTargetHeight - info.altitudeGoalFeet) > 60 {
                        nationalsTargetHeight = min(max(info.altitudeGoalFeet, nationalsDefaultAltitudeRange.lowerBound), nationalsDefaultAltitudeRange.upperBound)
                        nationalsTargetText = String(Int(nationalsTargetHeight))
                    }
                }
            }
            .onDisappear {
                resetNationalsInteractionState()
            }
            .task(id: insightsCalculationKey) {
                await refreshInsightsCache()
            }
        }
    }

    private var calibrationCard: some View {
        let flights = modelFlights
        let usableFlights = flights.filter { $0.measuredAltitudeFeet.isFinite }
        let meanError = cachedCalibrationMeanError
        let readiness = modelReadiness(for: usableFlights)
        return VStack(alignment: .leading, spacing: 12) {
            Text("AI Calibration")
                .font(.title3.bold())
            Text("\(usableFlights.count) recent flights are feeding the fast field model.")
                .foregroundStyle(.secondary)
            Gauge(value: readiness) {
                Text("Model readiness")
            }
            .tint(Color.arcMint)
            Text(readiness >= 1 ? "Model ready" : "\(Int(readiness * 100))% ready")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(readiness >= 1 ? Color.arcMint : Color.arcAmber)
            if let meanError {
                Text("Average back-test miss: about \(Int(meanError)) ft.")
                    .font(.footnote.weight(.semibold))
            } else {
                Text("Log at least 4 flights with different masses or weather conditions to unlock stronger calibration.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcAmber)
            }
            Text(calibrationHint(for: usableFlights))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var predictionCard: some View {
        let optimization = currentOptimization
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Current prediction")
                        .foregroundStyle(.secondary)
                    if let optimization {
                        Text("\(Int(optimization.suggestedMassGrams)) g")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                        Text(store.flightMode == .hobby && hobbyMaxAltitude ? "Suggested loaded weight for max altitude" : "Suggested loaded weight for \(Int(targetAltitudeForAI)) ft")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.arcAmber)
                    } else {
                        Text("-- g")
                            .font(.system(size: 44, weight: .black, design: .rounded))
                        Text("Add a rocket and motor to calculate weight")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.arcAmber)
                    }
                }
                Spacer()
                Gauge(value: optimization?.confidence ?? prediction.confidence) {
                    Text("Confidence")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Color.arcMint)
            }
            if let optimization {
                Text("Predicted apogee at that weight: \(Int(optimization.suggestedAltitudeFeet)) ft with \(Int(optimization.confidence * 100))% confidence.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(Int(prediction.confidence * 100))% confidence using the \(prediction.displayMethod).")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Target apogee", systemImage: "scope")
                Spacer()
                Text("\(Int(targetAltitudeForAI)) ft")
                    .font(.headline)
                    .foregroundStyle(Color.arcAmber)
            }
            .padding()
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

            Picker("Rocket filter", selection: $selectedRocketID) {
                Text("All rockets").tag(Optional<UUID>.none)
                ForEach(store.rockets) { rocket in
                    Text(rocket.name).tag(Optional(rocket.id))
                }
            }
            .pickerStyle(.menu)

            if store.flightMode == .hobby {
                hobbyAIControls
            }

            if let optimization {
                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Tuning")
                        .font(.headline)
                    if store.flightMode == .hobby {
                        Text(hobbyMaxAltitude ? "Goal: as high as possible" : "Goal: \(Int(hobbyTargetHeight)) ft")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.arcAmber)
                    }
                    Text("Suggested loaded mass: \(Int(optimization.suggestedMassGrams)) g (\(Int(optimization.massDeltaGrams)) g delta)")
                    Text("Predicted altitude at that mass: \(Int(optimization.suggestedAltitudeFeet)) ft")
                    if let drill = optimization.reusableDelayDrillSeconds {
                        Text("Reusable delay adjustment: about \(String(format: "%.1f", drill)) seconds toward the time window")
                    }
                    if let reefedCentimeters = optimization.suggestedReefedCentimeters {
                        Text("Parachute reefing: about \(String(format: "%.1f", reefedCentimeters)) cm reefed for the time window")
                    }
                    ForEach(optimization.notes, id: \.self) { note in
                        Text("• \(note)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .cardStyle()
    }

    private var hobbyAIControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hobby AI Goal")
                .font(.headline)
            Toggle("Calculate as high as possible", isOn: $hobbyMaxAltitude)
                .toggleStyle(.switch)
            if !hobbyMaxAltitude {
                NumberField(title: "Target Height", value: $hobbyTargetHeight, suffix: "ft")
            }
        }
        .padding()
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func aiOptimization(for rocket: Rocket, motor: MotorSpec) -> OptimizationResult {
        let weather = baselineWeatherForPrediction
        let flights = modelFlights

        if store.flightMode == .hobby, hobbyMaxAltitude {
            return PredictionEngine.maximizeAltitude(
                flights: flights,
                rocket: rocket,
                selectedMotor: motor,
                weather: weather,
                isReloadableMotor: effectiveMotorIsReloadable
            )
        }

        return PredictionEngine.optimizeForTarget(
            flights: flights,
            rocket: rocket,
            selectedMotor: motor,
            weather: weather,
            targetAltitudeFeet: targetAltitudeForAI,
            targetFlightTimeRange: store.isCompetitionMode ? store.syncedCompetitionInfo.flightTimeRange : nil,
            isReloadableMotor: effectiveMotorIsReloadable
        )
    }

    private func normalizeInsightsSelections() {
        if let selectedRocketID,
           !store.rockets.contains(where: { $0.id == selectedRocketID }) {
            self.selectedRocketID = nil
        }

        let currentMotorIsAvailable = availableMotors.contains { $0.designation == predictedMotorDesignation }
        if !currentMotorIsAvailable {
            predictedMotorDesignation = selectedRocketForInsights?.defaultMotorDesignation ?? availableMotors.first?.designation ?? predictedMotorDesignation
        }
        if !availableMotors.contains(where: { $0.designation == predictedMotorDesignation }),
           let firstMotor = availableMotors.first {
            predictedMotorDesignation = firstMotor.designation
        }

        selectedNationalsGraphTarget = nil
    }

    private var recommendationCard: some View {
        let recommendationConfidence = currentOptimization?.confidence ?? prediction.confidence
        return VStack(alignment: .leading, spacing: 12) {
            Text("Smart Recommendations")
                .font(.title3.bold())
            Text("Recommendation confidence: \(confidenceLabel(recommendationConfidence)) based on today's weather, selected motor, similar logged flights, and video-analyzed data.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(confidenceColor(recommendationConfidence))
            if let reefingRecommendation {
                VStack(alignment: .leading, spacing: 6) {
                    Label(reefingRecommendation.title, systemImage: "parachute")
                        .font(.headline)
                    Text(reefingRecommendation.detail)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(priorityColor(reefingRecommendation.priority).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(priorityColor(reefingRecommendation.priority).opacity(0.5)))
            }
            ForEach(cachedRecommendations) { recommendation in
                VStack(alignment: .leading, spacing: 6) {
                    Text(recommendation.title)
                        .font(.headline)
                    Text(recommendation.detail)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(priorityColor(recommendation.priority).opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(priorityColor(recommendation.priority).opacity(0.5)))
            }
        }
        .cardStyle()
    }

    private var dataSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI Data Summary", systemImage: "sparkles")
                .font(.title3.bold())
            Text(cachedDataSummary.headline)
                .font(.headline)
            ForEach(cachedDataSummary.insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(Color.arcMint)
                        .frame(width: 7, height: 7)
                        .padding(.top, 7)
                    Text(insight)
                        .foregroundStyle(.secondary)
                }
            }
            if let nextStep = cachedDataSummary.nextStep {
                Text(nextStep)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcAmber)
                    .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    private var todayConditionsCard: some View {
        let weather = baselineWeatherForPrediction
        return VStack(alignment: .leading, spacing: 10) {
            Label("Today's Calculation Snapshot", systemImage: "sun.max.fill")
                .font(.title3.bold())
            Text("Target: \(Int(targetAltitudeForAI)) ft")
            Text("Motor: \(predictedMotorDesignation)")
            Text("Weather: \(Int(weather.temperatureF.rounded())) F, \(Int(weather.windMPH.rounded())) mph wind, \(Int(weather.humidityPercent.rounded()))% humidity")
            Text("Loaded mass baseline: \(Int(baselineMassForPrediction.rounded())) g")
            Text("Similar flights, same motor, recent logs, weather matches, and analyzed videos are weighted most heavily.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        if confidence >= 0.75 { return "High" }
        if confidence >= 0.55 { return "Medium" }
        return "Building"
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.75 { return Color.arcMint }
        if confidence >= 0.55 { return Color.arcAmber }
        return Color.arcOrange
    }

    private var nationalsPlannerCard: some View {
        let season = String(store.syncedCompetitionInfo.seasonYear)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Nationals Planner")
                .font(.title3.bold())
            Text(verbatim: "Official ARC \(season) national target is \(Int(store.syncedCompetitionInfo.altitudeGoalFeet)) ft with a \(Int(store.syncedCompetitionInfo.flightTimeRange.lowerBound))-\(Int(store.syncedCompetitionInfo.flightTimeRange.upperBound)) s flight window. The \(Int(nationalsPlanningRange.lowerBound))-\(Int(nationalsPlanningRange.upperBound)) ft band below is a derived tuning range for practice and planning, not an official scoring range.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Planning target")
                    Spacer()
                    HStack(spacing: 6) {
                        TextField("750", text: $nationalsTargetText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.headline)
                            .frame(width: 56)
                            .onChange(of: nationalsTargetText) { _, text in
                                applyNationalsTargetText(text)
                            }
                        Text("ft")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                nationalsTargetSlider
                    .onChange(of: nationalsTargetHeight) { _, newValue in
                        let newText = String(Int(newValue.rounded()))
                        if nationalsTargetText != newText {
                            nationalsTargetText = newText
                        }
                        keepNationalsTargetVisible()
                        selectedNationalsGraphTarget = nil
                    }
                HStack {
                    Text("\(Int(nationalsDefaultAltitudeRange.lowerBound)) ft")
                    Spacer()
                    Text("Official target \(Int(store.syncedCompetitionInfo.altitudeGoalFeet)) ft")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(nationalsDefaultAltitudeRange.upperBound)) ft")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !nationalsLoggedFlights.isEmpty {
                Chart {
                    ForEach(nationalsLoggedFlights) { flight in
                        let height = plannerHeight(for: flight)
                        PointMark(
                            x: .value("Height", height),
                            y: .value("Logged Mass", flight.rocketMassGrams)
                        )
                        .foregroundStyle(Color.arcAmber)
                        .symbolSize(70)
                        if selectedNationalsFlight?.id == flight.id {
                            PointMark(
                                x: .value("Selected Height", height),
                                y: .value("Selected Mass", flight.rocketMassGrams)
                            )
                            .foregroundStyle(Color.arcOrange)
                            .symbolSize(130)
                        }
                    }

                    ForEach(nationalsBestFitPoints) { fit in
                        LineMark(
                            x: .value("Height", fit.x),
                            y: .value("Best Fit Mass", fit.y)
                        )
                        .foregroundStyle(Color.arcMint)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                }
                .chartXAxisLabel("Height (ft)")
                .chartYAxisLabel("Weight (g)")
                .chartXScale(domain: nationalsVisibleXDomain)
                .chartYScale(domain: nationalsVisibleYDomain)
                .chartPlotStyle { plotArea in
                    plotArea.clipped()
                }
                .chartOverlay { chartProxy in
                    nationalsTargetOverlay(chartProxy: chartProxy)
                }
                .clipped()
                .frame(height: 270)
                Text("Dots are your flight logs. X is wanted height when available, otherwise measured height. Y is logged weight. The mint line is the best-fit trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Log flights to populate this height vs. weight graph.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let flight = selectedNationalsFlight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Closest logged flight")
                        .font(.headline)
                    Text("Height \(Int(plannerHeight(for: flight))) ft, flew \(Int(flight.measuredAltitudeFeet)) ft at \(Int(flight.rocketMassGrams)) g.")
                    Text("Score for that log: \(store.scoreSummary(for: flight).totalPoints.map(String.init) ?? "Disqualified")")
                }
                .padding(.top, 2)
            }
        }
        .cardStyle()
    }

    private var nationalsTargetSlider: some View {
        GeometryReader { geometry in
            let range = nationalsDefaultAltitudeRange
            let width = max(geometry.size.width, 1)
            let progress = CGFloat((nationalsTargetHeight - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clampedProgress = min(max(progress, 0), 1)
            let thumbX = clampedProgress * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.14))
                    .frame(height: 8)
                Capsule()
                    .fill(Color.arcMint)
                    .frame(width: max(0, thumbX), height: 8)
                Circle()
                    .fill(Color.arcAmber)
                    .frame(width: 30, height: 30)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                    .offset(x: min(max(thumbX - 15, 0), max(width - 30, 0)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        isAdjustingNationalsSlider = true
                        updateNationalsSlider(from: value.location.x, width: width)
                    }
                    .onEnded { value in
                        updateNationalsSlider(from: value.location.x, width: width)
                        finishNationalsSliderAdjustment()
                    }
            )
            .accessibilityLabel("Planning target")
            .accessibilityValue("\(Int(nationalsTargetHeight)) feet")
        }
        .frame(height: 44)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func nationalsPanGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if nationalsDragStartXCenter == nil {
                    nationalsDragStartXCenter = nationalsXCenter
                    nationalsDragStartYCenter = nationalsYCenter ?? ((nationalsMassDomain.lowerBound + nationalsMassDomain.upperBound) / 2)
                }

                let width = max(Double(size.width), 1)
                let height = max(Double(size.height), 1)
                let xDelta = Double(value.translation.width) / width * nationalsXSpan
                let yDelta = Double(value.translation.height) / height * nationalsEffectiveYSpan
                nationalsXCenter = clamp((nationalsDragStartXCenter ?? nationalsXCenter) - xDelta, min: nationalsXSpan / 2, max: 2_500)
                nationalsYCenter = (nationalsDragStartYCenter ?? 0) + yDelta
                keepNationalsTargetVisible()
            }
            .onEnded { _ in
                nationalsDragStartXCenter = nil
                nationalsDragStartYCenter = nil
            }
    }

    private var nationalsZoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if nationalsZoomStartXSpan == nil {
                    nationalsZoomStartXSpan = nationalsXSpan
                    nationalsZoomStartYSpan = nationalsEffectiveYSpan
                }

                let factor = 1 / max(value.magnification, 0.2)
                nationalsXSpan = clamp((nationalsZoomStartXSpan ?? nationalsXSpan) * factor, min: 20, max: 900)
                nationalsYSpan = clamp((nationalsZoomStartYSpan ?? nationalsEffectiveYSpan) * factor, min: 8, max: 600)
                keepNationalsTargetVisible()
            }
            .onEnded { _ in
                nationalsZoomStartXSpan = nil
                nationalsZoomStartYSpan = nil
            }
    }

    private func resetNationalsChartView() {
        nationalsXCenter = 700
        nationalsXSpan = 200
        nationalsYCenter = nil
        nationalsYSpan = nil
        selectedNationalsGraphTarget = nil
    }

    private func resetNationalsInteractionState() {
        isAdjustingNationalsSlider = false
        nationalsDragStartXCenter = nil
        nationalsDragStartYCenter = nil
        nationalsZoomStartXSpan = nil
        nationalsZoomStartYSpan = nil
    }

    private func updateNationalsSlider(from xLocation: CGFloat, width: CGFloat) {
        let safeWidth = max(Double(width), 1)
        let progress = clamp(Double(xLocation) / safeWidth, min: 0, max: 1)
        let range = nationalsDefaultAltitudeRange
        let rawValue = range.lowerBound + progress * (range.upperBound - range.lowerBound)
        let steppedValue = rawValue.rounded()
        nationalsTargetHeight = clamp(steppedValue, min: range.lowerBound, max: range.upperBound)
    }

    private func finishNationalsSliderAdjustment() {
        store.updateTargetAltitude(nationalsTargetHeight)
        resetNationalsInteractionState()
    }

    @MainActor
    private func refreshInsightsCache() async {
        guard !isAdjustingNationalsSlider else { return }

        let flights = modelFlights
        let input = predictionInput
        let targetAltitude = targetAltitudeForAI
        let targetFlightTimeRange = store.isCompetitionMode ? store.syncedCompetitionInfo.flightTimeRange : nil
        let rocket = selectedRocketForInsights
        let motor = selectedMotorForInsights
        let weather = baselineWeatherForPrediction
        let flightMode = store.flightMode
        let hobbyMaxAltitude = hobbyMaxAltitude
        let reloadable = effectiveMotorIsReloadable

        isRefreshingInsights = true
        let result = await Task.detached(priority: .utility) {
            let prediction = PredictionEngine.predict(flights: flights, input: input)
            let optimization: OptimizationResult?
            if let rocket, let motor {
                if flightMode == .hobby, hobbyMaxAltitude {
                    optimization = PredictionEngine.maximizeAltitude(
                        flights: flights,
                        rocket: rocket,
                        selectedMotor: motor,
                        weather: weather,
                        isReloadableMotor: reloadable
                    )
                } else {
                    optimization = PredictionEngine.optimizeForTarget(
                        flights: flights,
                        rocket: rocket,
                        selectedMotor: motor,
                        weather: weather,
                        targetAltitudeFeet: targetAltitude,
                        targetFlightTimeRange: targetFlightTimeRange,
                        isReloadableMotor: reloadable
                    )
                }
            } else {
                optimization = nil
            }
            let recommendations = PredictionEngine.recommendations(
                flights: flights,
                input: input,
                targetAltitude: targetAltitude,
                targetFlightTimeRange: targetFlightTimeRange
            )
            let meanError = Self.computeCalibrationMeanError(
                for: flights.filter { $0.measuredAltitudeFeet.isFinite },
                modelFlights: flights,
                rocket: rocket
            )
            let summary = Self.summarizeData(
                flights: flights,
                targetAltitude: targetAltitude,
                targetFlightTimeRange: targetFlightTimeRange,
                optimization: optimization
            )
            return (prediction, optimization, recommendations, meanError, summary)
        }.value

        cachedPrediction = result.0
        cachedOptimization = result.1
        cachedRecommendations = result.2
        cachedCalibrationMeanError = result.3
        cachedDataSummary = result.4
        isRefreshingInsights = false
    }

    private func keepNationalsTargetVisible() {
        let padding = nationalsTargetPadding
        let leftmostCenter = nationalsTargetHeight + padding - nationalsXSpan / 2
        let rightmostCenter = nationalsTargetHeight - padding + nationalsXSpan / 2

        if leftmostCenter <= rightmostCenter {
            nationalsXCenter = clamp(nationalsXCenter, min: leftmostCenter, max: rightmostCenter)
        } else {
            nationalsXCenter = nationalsTargetHeight
        }
    }

    private func applyNationalsTargetText(_ text: String) {
        let digits = text.filter(\.isNumber)
        guard digits == text, let value = Double(digits) else {
            return
        }

        guard nationalsDefaultAltitudeRange.contains(value) else {
            return
        }

        if abs(nationalsTargetHeight - value) > 0.1 {
            nationalsTargetHeight = value
            keepNationalsTargetVisible()
        }
    }

    @ViewBuilder
    private func nationalsTargetOverlay(chartProxy: ChartProxy) -> some View {
        GeometryReader { geometry in
            if let plotFrame = chartProxy.plotFrame,
               let targetX = chartProxy.position(forX: nationalsTargetHeight) {
                let frame = geometry[plotFrame]
                let lineX = frame.minX + targetX

                if frame.minX...frame.maxX ~= lineX {
                    Path { path in
                        path.move(to: CGPoint(x: lineX, y: frame.minY))
                        path.addLine(to: CGPoint(x: lineX, y: frame.maxY))
                    }
                    .stroke(Color.arcOrange, style: StrokeStyle(lineWidth: 2, dash: [6, 6]))
                        .accessibilityHidden(true)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func refreshMotorStatus() async {
        do {
            let status = try await ARCWebsiteService.lookupMotorStatus(
                designation: predictedMotorDesignation,
                seasonYear: store.syncedCompetitionInfo.seasonYear
            )
            onlineMotorReloadable = status.isReloadable
            onlineMotorStatusMessage = "\(status.statusMessage) Delay-drill guidance only appears for motors the ARC list marks as reloadable."
        } catch {
            onlineMotorReloadable = nil
            let fallback = selectedMotorForInsights?.reloadable == true ? "RMS" : "single-use"
            onlineMotorStatusMessage = "Could not refresh the ARC motor list right now. Falling back to the built-in \(fallback) flag for this motor."
        }
    }

    private func bestFitPoints(_ data: [(Double, Double)], xDomain: ClosedRange<Double>? = nil) -> [TrendPoint] {
        let finiteData = data.filter { $0.0.isFinite && $0.1.isFinite }.sorted { $0.0 < $1.0 }
        guard finiteData.count >= 2 else { return [] }
        let xs = finiteData.map(\.0)
        let ys = finiteData.map(\.1)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let numerator = zip(xs, ys).reduce(0) { total, pair in
            total + (pair.0 - meanX) * (pair.1 - meanY)
        }
        let denominator = xs.reduce(0) { total, x in
            let delta = x - meanX
            return total + delta * delta
        }
        guard denominator > 0, let minX = xs.min(), let maxX = xs.max() else { return [] }
        let slope = numerator / denominator
        let intercept = meanY - slope * meanX
        let startX = xDomain?.lowerBound ?? minX
        let endX = xDomain?.upperBound ?? maxX
        return [
            TrendPoint(x: startX, y: slope * startX + intercept),
            TrendPoint(x: endX, y: slope * endX + intercept)
        ]
    }

    private func calibrationMeanError(for flights: [Flight]) -> Double? {
        guard flights.count >= 4 else { return nil }
        let sampledFlights = Self.downsample(flights, limit: 6)
        let errors = sampledFlights.map { flight in
            let input = PredictionInput(
                motorType: flight.motorType,
                motorDesignation: flight.motorDesignation,
                rocketMassGrams: flight.rocketMassGrams,
                temperatureF: flight.weather.temperatureF,
                windMPH: flight.weather.windMPH,
                humidityPercent: flight.weather.humidityPercent,
                rocketMaterial: selectedRocketForInsights?.material ?? .cardboard,
                parachuteSizeInches: flight.parachuteSizeInches,
                rocketHeightMillimeters: selectedRocketForInsights?.heightMillimeters ?? 700,
                rocketWidthMillimeters: selectedRocketForInsights?.widthMillimeters ?? 66
            )
            let predicted = PredictionEngine.predict(flights: modelFlights.filter { $0.id != flight.id }, input: input)
            return abs(predicted.altitudeFeet - flight.measuredAltitudeFeet)
        }
        return errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
    }

    nonisolated private static func computeCalibrationMeanError(for flights: [Flight], modelFlights: [Flight], rocket: Rocket?) -> Double? {
        guard flights.count >= 4 else { return nil }
        let sampledFlights = Self.downsample(flights, limit: 5)
        let rocketMaterial = rocket?.material ?? .cardboard
        let rocketHeight = rocket?.heightMillimeters ?? 700
        let rocketWidth = rocket?.widthMillimeters ?? 66
        let errors = sampledFlights.map { flight in
            let input = PredictionInput(
                motorType: flight.motorType,
                motorDesignation: flight.motorDesignation,
                rocketMassGrams: flight.rocketMassGrams,
                temperatureF: flight.weather.temperatureF,
                windMPH: flight.weather.windMPH,
                humidityPercent: flight.weather.humidityPercent,
                rocketMaterial: rocketMaterial,
                parachuteSizeInches: flight.parachuteSizeInches,
                rocketHeightMillimeters: rocketHeight,
                rocketWidthMillimeters: rocketWidth
            )
            let predicted = PredictionEngine.predict(flights: modelFlights.filter { $0.id != flight.id }, input: input)
            return abs(predicted.altitudeFeet - flight.measuredAltitudeFeet)
        }
        return errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
    }

    nonisolated private static func summarizeData(
        flights: [Flight],
        targetAltitude: Double,
        targetFlightTimeRange: ClosedRange<Double>?,
        optimization: OptimizationResult?
    ) -> AIDataSummary {
        let usable = flights.filter { !$0.excludedFromAI && $0.measuredAltitudeFeet.isFinite && $0.rocketMassGrams.isFinite }
        guard !usable.isEmpty else {
            return AIDataSummary(
                headline: "No flight data yet.",
                insights: [
                    "Add a few flights with altitude, loaded mass, motor, weather, flight time, and reefed centimeters so the model can learn from your team.",
                    "Spreadsheet imports and analyzed videos will also feed this summary once they create editable flight logs."
                ],
                nextStep: "Best next step: log or import at least 3 flights for the same rocket."
            )
        }

        let altitudes = usable.map(\.measuredAltitudeFeet)
        let masses = usable.map(\.rocketMassGrams)
        let averageAltitude = average(altitudes)
        let averageMass = average(masses)
        let bestAltitude = altitudes.max() ?? averageAltitude
        let targetErrors = usable.map { abs(($0.targetAltitudeFeet ?? targetAltitude) - $0.measuredAltitudeFeet) }
        let averageTargetMiss = average(targetErrors)
        let bestTargetMiss = targetErrors.min() ?? averageTargetMiss
        let timedFlights = usable.filter { $0.flightTimeSeconds != nil }
        let reefedFlights = timedFlights.filter { $0.parachuteReefedCentimeters != nil }
        let videoAnalyzedFlights = usable.filter { flight in
            flight.attachments.contains { ($0.analysisSummary?.isEmpty == false) || $0.videoEstimatedFlightTimeSeconds != nil }
        }
        let importedFlights = usable.filter { $0.notes.localizedCaseInsensitiveContains("import") }
        let slope = linearSlope(x: usable.map(\.rocketMassGrams), y: usable.map(\.measuredAltitudeFeet))
        let windSlope = linearSlope(x: usable.map(\.weather.windMPH), y: usable.map(\.measuredAltitudeFeet))

        let groupedByWantedAltitude = Dictionary(grouping: usable) { flight in
            Int(((flight.targetAltitudeFeet ?? targetAltitude) / 25).rounded() * 25)
        }
        let bestGroup = groupedByWantedAltitude
            .filter { $0.value.count >= 2 }
            .map { target, group -> (target: Int, count: Int, miss: Double) in
                let misses = group.map { abs(($0.targetAltitudeFeet ?? Double(target)) - $0.measuredAltitudeFeet) }
                return (target, group.count, average(misses))
            }
            .min { $0.miss < $1.miss }

        let trendText: String
        if usable.count >= 3, let slope, slope.isFinite, abs(slope) >= 0.05 {
            let direction = slope < 0 ? "more weight has usually lowered altitude" : "more weight has usually raised altitude"
            trendText = "Weight trend: \(direction) by about \(String(format: "%.1f", abs(slope))) ft per gram in the current filtered data."
        } else {
            trendText = "Weight trend: not enough varied mass data yet to trust a precise ft-per-gram slope."
        }

        let weatherText: String
        if usable.count >= 4, let windSlope, windSlope.isFinite, abs(windSlope) >= 1.0 {
            let direction = windSlope < 0 ? "lower" : "higher"
            weatherText = "Weather signal: higher wind has correlated with \(direction) altitude by about \(Int(abs(windSlope).rounded())) ft per mph."
        } else {
            weatherText = "Weather signal: keep logging live weather; the current wind/altitude relationship is still weak."
        }

        var insights: [String] = [
            "\(usable.count) flights are feeding the model. Average altitude is \(Int(averageAltitude.rounded())) ft, best altitude is \(Int(bestAltitude.rounded())) ft, and average loaded mass is \(Int(averageMass.rounded())) g.",
            "Target accuracy: average miss is \(Int(averageTargetMiss.rounded())) ft, with the best logged miss at \(Int(bestTargetMiss.rounded())) ft.",
            trendText,
            weatherText
        ]

        if let optimization {
            let massDirection = optimization.massDeltaGrams < 0 ? "remove" : "add"
            insights.append("Current tuner output: \(massDirection) about \(Int(abs(optimization.massDeltaGrams).rounded())) g to aim near \(Int(targetAltitude.rounded())) ft; predicted apogee is \(Int(optimization.suggestedAltitudeFeet.rounded())) ft.")
        } else {
            insights.append("Current tuner output: add a rocket and selected motor so the app can summarize the exact weight recommendation.")
        }

        if let targetFlightTimeRange {
            if timedFlights.isEmpty {
                insights.append("Timing: no flight-time logs yet, so delay drilling and reefing advice is still low confidence.")
            } else {
                let averageTime = average(timedFlights.compactMap(\.flightTimeSeconds))
                let timeStatus = targetFlightTimeRange.contains(averageTime) ? "inside" : "outside"
                insights.append("Timing: \(timedFlights.count) timed flights average \(String(format: "%.1f", averageTime)) s, \(timeStatus) the \(Int(targetFlightTimeRange.lowerBound))-\(Int(targetFlightTimeRange.upperBound)) s window.")
            }

            if !reefedFlights.isEmpty {
                let averageReef = average(reefedFlights.compactMap(\.parachuteReefedCentimeters))
                insights.append("Recovery data: \(reefedFlights.count) logs include reefing, averaging \(String(format: "%.1f", averageReef)) cm reefed.")
            }
        }

        if let bestGroup {
            insights.append("Best repeated target group: flights aimed near \(bestGroup.target) ft average \(Int(bestGroup.miss.rounded())) ft off across \(bestGroup.count) logs.")
        }

        if videoAnalyzedFlights.isEmpty {
            insights.append("Video coverage: no analyzed videos are attached to these logs yet.")
        } else {
            insights.append("Video coverage: \(videoAnalyzedFlights.count) flights include analyzed video signals that can explain boost, coast, deployment, or descent issues.")
        }

        if !importedFlights.isEmpty {
            insights.append("Imported sheet data: \(importedFlights.count) logs appear to come from flight-sheet imports and are included in the same calculations.")
        }

        let nextStep: String
        if usable.count < 4 {
            nextStep = "Best next step: add more flights before trusting small weight changes."
        } else if Set(usable.map { Int($0.rocketMassGrams / 10) }).count < 3 {
            nextStep = "Best next step: fly the same setup at 2-3 different masses so the weight recommendation tightens."
        } else if targetFlightTimeRange != nil && reefedFlights.count < 3 {
            nextStep = "Best next step: log flight time and reefed centimeters on the next few flights so recovery advice improves."
        } else if videoAnalyzedFlights.isEmpty {
            nextStep = "Best next step: analyze one launch video so the app can connect performance changes to what happened in flight."
        } else {
            nextStep = "Best next step: repeat the current recommended setup and use the result to tighten the model."
        }

        return AIDataSummary(
            headline: "Your logbook is strongest around \(Int(averageMass.rounded())) g and \(Int(averageAltitude.rounded())) ft.",
            insights: Array(insights.prefix(8)),
            nextStep: nextStep
        )
    }

    private func calibrationHint(for flights: [Flight]) -> String {
        if flights.count < 4 {
            return "Best next step: log more flights before trusting fine weight changes."
        }
        let masses = Set(flights.map { Int($0.rocketMassGrams / 10) * 10 })
        if masses.count < 3 {
            return "Best next step: test at a few different loaded masses so the weight tuner learns the slope."
        }
        let motors = Set(flights.map(\.motorDesignation))
        if motors.count < 2 {
            return "Best next step: add flights on another motor if you want motor-selection recommendations to improve."
        }
        return "Calibration looks useful. Keep logging flights in varied weather to tighten confidence."
    }

    private func modelReadiness(for flights: [Flight]) -> Double {
        guard !flights.isEmpty else { return 0 }
        let flightScore = min(Double(flights.count) / 8, 1)
        let massBuckets = Set(flights.map { Int($0.rocketMassGrams / 10) })
        let massScore = min(Double(massBuckets.count) / 3, 1)
        let motorScore = min(Double(Set(flights.map(\.motorDesignation)).count) / 2, 1)
        let weatherScore = flights.contains { $0.weather.windMPH > 0 || $0.weather.temperatureF != 72 } ? 1.0 : 0.55
        if flights.count >= 4 && massBuckets.count >= 2 {
            return min(max((flightScore * 0.5) + (massScore * 0.25) + (motorScore * 0.15) + (weatherScore * 0.10), 0.75), 1)
        }
        return min((flightScore * 0.65) + (massScore * 0.25) + (weatherScore * 0.10), 0.72)
    }

    private func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }

    private func paddedDomain(_ values: [Double], minimumPadding: Double) -> ClosedRange<Double> {
        let finite = values.filter(\.isFinite)
        guard let minValue = finite.min(), let maxValue = finite.max() else {
            return 0...1
        }
        let padding = max(minimumPadding, (maxValue - minValue) * 0.18)
        return (minValue - padding)...(maxValue + padding)
    }

    nonisolated private static func downsample<T>(_ values: [T], limit: Int) -> [T] {
        guard values.count > limit, limit > 1 else { return values }
        let step = Double(values.count - 1) / Double(limit - 1)
        return (0..<limit).map { values[Int((Double($0) * step).rounded())] }
    }

    nonisolated private static func average(_ values: [Double]) -> Double {
        let finite = values.filter(\.isFinite)
        guard !finite.isEmpty else { return 0 }
        return finite.reduce(0, +) / Double(finite.count)
    }

    nonisolated private static func linearSlope(x: [Double], y: [Double]) -> Double? {
        let pairs = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        guard pairs.count >= 3 else { return nil }
        let xs = pairs.map(\.0)
        let ys = pairs.map(\.1)
        let meanX = average(xs)
        let meanY = average(ys)
        let denominator = xs.reduce(0) { total, value in
            let delta = value - meanX
            return total + delta * delta
        }
        guard denominator > 0 else { return nil }
        let numerator = zip(xs, ys).reduce(0) { total, pair in
            total + (pair.0 - meanX) * (pair.1 - meanY)
        }
        return numerator / denominator
    }

    private func priorityColor(_ priority: Recommendation.Priority) -> Color {
        switch priority {
        case .high: return Color.arcOrange
        case .medium: return Color.arcAmber
        case .low: return Color.arcMint
        }
    }
}

private struct TrendPoint: Identifiable {
    var id: String { "\(x)-\(y)" }
    var x: Double
    var y: Double
}

private struct AIDataSummary {
    var headline: String
    var insights: [String]
    var nextStep: String?

    static let empty = AIDataSummary(
        headline: "Summarizing your flight data...",
        insights: ["The summary updates automatically when logs, imports, videos, weather, or targets change."],
        nextStep: nil
    )
}
