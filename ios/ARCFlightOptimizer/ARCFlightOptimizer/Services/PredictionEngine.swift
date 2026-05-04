import Foundation

enum PredictionEngine {
    static func predict(flights: [Flight], input: PredictionInput) -> Prediction {
        let usableFlights = trainingFlights(from: flights, input: input).filter { $0.measuredAltitudeFeet.isFinite }
        let priorAltitude = physicsPriorAltitude(for: input)

        guard usableFlights.count >= 4 else {
            let average = usableFlights.isEmpty
                ? priorAltitude
                : usableFlights.map(\.measuredAltitudeFeet).reduce(0, +) / Double(usableFlights.count)
            let blended = usableFlights.isEmpty
                ? priorAltitude
                : priorAltitude * 0.55 + average * 0.45
            return Prediction(
                altitudeFeet: sanitizedAltitude(blended).rounded(),
                confidence: min(0.45, Double(usableFlights.count) * 0.12),
                method: "baseline"
            )
        }

        let rawFeatures = usableFlights.map { rawFeatureVector(inputFromFlight($0)) }
        let normalizer = FeatureNormalizer(rows: rawFeatures)
        let features = rawFeatures.map { normalizer.normalized($0) }

        let targets = usableFlights.map(\.measuredAltitudeFeet)
        let width = features[0].count
        var xtx = Array(repeating: Array(repeating: 0.0, count: width), count: width)
        var xty = Array(repeating: 0.0, count: width)

        // Ridge regression keeps field predictions stable with small, noisy ARC launch datasets.
        // Inputs include motor impulse, mass, weather, and key airframe variables.
        // The goal is an explainable field model rather than a black-box predictor.
        for row in 0..<features.count {
            for i in 0..<width {
                xty[i] += features[row][i] * targets[row]
                for j in 0..<width {
                    xtx[i][j] += features[row][i] * features[row][j]
                }
            }
        }

        for i in 1..<width {
            xtx[i][i] += 0.25
        }

        let weights = solveLinearSystem(matrix: xtx, values: xty)
        let regressionAltitude = dot(normalizer.normalized(rawFeatureVector(input)), weights)
        let altitude = sanitizedAltitude(regressionAltitude * 0.72 + priorAltitude * 0.28)
        let meanError = zip(features, targets)
            .map { row, actual in abs(dot(row, weights) - actual) }
            .reduce(0, +) / Double(usableFlights.count)

        return Prediction(
            altitudeFeet: altitude.rounded(),
            confidence: max(0.35, min(0.92, 1 - meanError / 180 + Double(usableFlights.count) * 0.015)),
            method: "regression"
        )
    }

    static func recommendations(
        flights: [Flight],
        input: PredictionInput,
        targetAltitude: Double,
        targetFlightTimeRange: ClosedRange<Double>? = nil
    ) -> [Recommendation] {
        let usableFlights = trainingFlights(from: flights, input: input).filter { $0.measuredAltitudeFeet.isFinite }
        let current = predict(flights: usableFlights, input: input)
        let delta = targetAltitude - current.altitudeFeet

        if abs(delta) <= 8 {
            return [
                Recommendation(
                    title: "Hold this setup",
                    detail: "The current model predicts \(Int(current.altitudeFeet)) ft, within \(Int(abs(delta))) ft of the \(Int(targetAltitude)) ft target. Keep the mass, motor, and recovery setup steady and log another repeat flight.",
                    priority: .low
                )
            ]
        }

        let slope = empiricalSlope(
            flights: usableFlights.filter { $0.motorDesignation == input.motorDesignation },
            x: \.rocketMassGrams,
            y: \.measuredAltitudeFeet
        ) ?? empiricalSlope(flights: usableFlights, x: \.rocketMassGrams, y: \.measuredAltitudeFeet)

        var output: [Recommendation] = []
        if let slope, abs(slope) > 0.08, abs(slope) < 8 {
            let rawMassChange = delta / slope
            let massChange = min(max(rawMassChange, -180), 180)
            let newMass = input.rocketMassGrams + massChange
            output.append(
                Recommendation(
                    title: massChange < 0 ? "Remove data-backed trim mass" : "Add data-backed trim mass",
                    detail: "Your logs show about \(String(format: "%.1f", abs(slope))) ft per gram for this setup. Aim near \(Int(newMass)) g loaded mass, a \(Int(massChange.rounded())) g change toward \(Int(targetAltitude)) ft.",
                    priority: abs(delta) > 35 ? .high : .medium
                )
            )
        } else {
            let tunedMass = bestMassFromModel(flights: usableFlights, input: input, targetAltitude: targetAltitude)
            let massDelta = tunedMass - input.rocketMassGrams
            output.append(
                Recommendation(
                    title: massDelta < 0 ? "Test a lighter data point" : "Test a heavier data point",
                    detail: "The logbook does not yet show a reliable mass-to-altitude slope. The stabilized model suggests testing around \(Int(tunedMass)) g, a \(Int(massDelta.rounded())) g change, then logging repeat flights to lock in the real slope.",
                    priority: .medium
                )
            )
        }

        if let motorRecommendation = motorRecommendation(flights: usableFlights, input: input, targetAltitude: targetAltitude) {
            output.append(motorRecommendation)
        } else if let nearby = nearbyMotor(for: input.motorDesignation, shouldIncrease: delta > 80), abs(delta) > 80 {
            output.append(
                Recommendation(
                    title: "Test \(nearby.designation) next",
                    detail: "Your logs do not yet have enough motor comparison data. Based on the current altitude miss, \(nearby.designation) is the next motor worth testing and logging.",
                    priority: .medium
                )
            )
        }

        if let targetFlightTimeRange {
            if let timing = timingRecommendation(flights: usableFlights, targetRange: targetFlightTimeRange) {
                output.append(timing)
            } else {
                output.append(
                    Recommendation(
                        title: "Log time and chute together",
                        detail: "Timing recommendations need flights with both flight time and parachute size. Add those to the next few logs so the app can calculate chute/delay changes from your own data.",
                        priority: .low
                    )
                )
            }
        }

        if output.isEmpty {
            output.append(
                Recommendation(
                    title: "Add more flight data",
                    detail: "Recommendations become data-based after you log altitude, loaded mass, motor, and weather for several flights.",
                    priority: .medium
                )
            )
        }

        return output
    }

    static func optimizeForTarget(
        flights: [Flight],
        rocket: Rocket,
        selectedMotor: MotorSpec,
        weather: Weather,
        targetAltitudeFeet: Double,
        targetFlightTimeRange: ClosedRange<Double>? = nil,
        isReloadableMotor: Bool? = nil
    ) -> OptimizationResult {
        let currentMass = rocket.dryMassGrams + 90
        let baseInput = PredictionInput(
            motorType: selectedMotor.motorClass,
            motorDesignation: selectedMotor.designation,
            rocketMassGrams: currentMass,
            temperatureF: weather.temperatureF,
            windMPH: weather.windMPH,
            humidityPercent: weather.humidityPercent,
            rocketMaterial: rocket.material,
            parachuteSizeInches: rocket.parachuteSizeInches,
            rocketHeightMillimeters: rocket.heightMillimeters,
            rocketWidthMillimeters: rocket.widthMillimeters
        )

        var bestMass = currentMass
        var bestPrediction = predict(flights: flights, input: baseInput)
        var bestError = abs(bestPrediction.altitudeFeet - targetAltitudeFeet)

        let coarseSearch = bestMassSearchRange(for: rocket, currentMass: currentMass)
        for step in stride(from: coarseSearch.lowerBound, through: coarseSearch.upperBound, by: 25) {
            let candidate = PredictionInput(
                motorType: baseInput.motorType,
                motorDesignation: baseInput.motorDesignation,
                rocketMassGrams: step,
                temperatureF: baseInput.temperatureF,
                windMPH: baseInput.windMPH,
                humidityPercent: baseInput.humidityPercent,
                rocketMaterial: baseInput.rocketMaterial,
                parachuteSizeInches: baseInput.parachuteSizeInches,
                rocketHeightMillimeters: baseInput.rocketHeightMillimeters,
                rocketWidthMillimeters: baseInput.rocketWidthMillimeters
            )
            let prediction = predict(flights: flights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitudeFeet)
            if error < bestError {
                bestMass = step
                bestPrediction = prediction
                bestError = error
            }
        }

        for step in stride(from: max(coarseSearch.lowerBound, bestMass - 35), through: min(coarseSearch.upperBound, bestMass + 35), by: 5) {
            var candidate = baseInput
            candidate.rocketMassGrams = step
            let prediction = predict(flights: flights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitudeFeet)
            if error < bestError {
                bestMass = step
                bestPrediction = prediction
                bestError = error
            }
        }

        let estimatedFlightTime = estimatedFlightTimeSeconds(rocket: rocket, massGrams: bestMass, weather: weather)
        let reloadable = isReloadableMotor ?? selectedMotor.reloadable
        let reefSuggestion = recommendedReefedCentimeters(
            flights: flights,
            targetRange: targetFlightTimeRange,
            estimatedFlightTime: estimatedFlightTime
        )
        let drillSuggestion: Double?
        if reloadable, let targetFlightTimeRange {
            drillSuggestion = recommendedDelayAdjustmentSeconds(
                estimatedFlightTime: estimatedFlightTime,
                targetRange: targetFlightTimeRange
            )
        } else {
            drillSuggestion = nil
        }

        var notes = [
            "Optimization uses past flights, selected motor impulse, airframe dimensions, parachute size, material, and current weather.",
            "Most similar flights for today's motor, weather, mass, and video-analyzed data are weighted more heavily.",
            "Suggested mass is relative to an estimated ready-to-fly baseline of about \(Int(currentMass)) g."
        ]
        if rocket.importedFromOpenRocket {
            notes.insert(
                "Using OpenRocket design data from \(rocket.openRocketFileName ?? "the imported file"): \(rocket.openRocketDesignSummary ?? "airframe mass and dimensions are feeding the optimizer").",
                at: 0
            )
        }
        if let targetFlightTimeRange {
            notes.append("Estimated flight time is about \(String(format: "%.1f", estimatedFlightTime)) s for a target window of \(Int(targetFlightTimeRange.lowerBound))-\(Int(targetFlightTimeRange.upperBound)) s.")
        }
        if let reefSuggestion {
            notes.append("Based on logged flight-time vs. reefing data, try about \(String(format: "%.1f", reefSuggestion)) cm of parachute reefing for the time window.")
        }
        if reloadable {
            notes.append("Delay drill guidance is approximate and should be checked against the manufacturer delay chart and safe test flights.")
        }

        return OptimizationResult(
            suggestedMassGrams: bestMass.rounded(),
            suggestedAltitudeFeet: bestPrediction.altitudeFeet,
            massDeltaGrams: (bestMass - currentMass).rounded(),
            confidence: bestPrediction.confidence,
            notes: notes,
            reusableDelayDrillSeconds: drillSuggestion,
            suggestedReefedCentimeters: reefSuggestion
        )
    }

    static func maximizeAltitude(
        flights: [Flight],
        rocket: Rocket,
        selectedMotor: MotorSpec,
        weather: Weather,
        isReloadableMotor: Bool? = nil
    ) -> OptimizationResult {
        let currentMass = rocket.dryMassGrams + 90
        let baseInput = PredictionInput(
            motorType: selectedMotor.motorClass,
            motorDesignation: selectedMotor.designation,
            rocketMassGrams: currentMass,
            temperatureF: weather.temperatureF,
            windMPH: weather.windMPH,
            humidityPercent: weather.humidityPercent,
            rocketMaterial: rocket.material,
            parachuteSizeInches: rocket.parachuteSizeInches,
            rocketHeightMillimeters: rocket.heightMillimeters,
            rocketWidthMillimeters: rocket.widthMillimeters
        )

        var bestMass = currentMass
        var bestPrediction = predict(flights: flights, input: baseInput)

        for step in stride(from: max(rocket.dryMassGrams, currentMass - 220), through: currentMass + 60, by: 16) {
            let candidate = PredictionInput(
                motorType: baseInput.motorType,
                motorDesignation: baseInput.motorDesignation,
                rocketMassGrams: step,
                temperatureF: baseInput.temperatureF,
                windMPH: baseInput.windMPH,
                humidityPercent: baseInput.humidityPercent,
                rocketMaterial: baseInput.rocketMaterial,
                parachuteSizeInches: baseInput.parachuteSizeInches,
                rocketHeightMillimeters: baseInput.rocketHeightMillimeters,
                rocketWidthMillimeters: baseInput.rocketWidthMillimeters
            )
            let prediction = predict(flights: flights, input: candidate)
            if prediction.altitudeFeet > bestPrediction.altitudeFeet {
                bestMass = step
                bestPrediction = prediction
            }
        }

        var notes = [
            "Max-altitude search uses past flights, selected motor impulse, airframe dimensions, parachute size, material, and current weather.",
            "Most similar flights for today's motor, weather, mass, and video-analyzed data are weighted more heavily.",
            "The model searched practical loaded masses from \(Int(max(rocket.dryMassGrams, currentMass - 160))) g to \(Int(currentMass + 40)) g."
        ]
        if rocket.importedFromOpenRocket {
            notes.insert(
                "Using OpenRocket design data from \(rocket.openRocketFileName ?? "the imported file"): \(rocket.openRocketDesignSummary ?? "airframe mass and dimensions are feeding the optimizer").",
                at: 0
            )
        }
        if isReloadableMotor ?? selectedMotor.reloadable {
            notes.append("Delay drill guidance is not shown for max altitude because there is no target flight-time window in Hobby mode.")
        }

        return OptimizationResult(
            suggestedMassGrams: bestMass.rounded(),
            suggestedAltitudeFeet: bestPrediction.altitudeFeet,
            massDeltaGrams: (bestMass - currentMass).rounded(),
            confidence: bestPrediction.confidence,
            notes: notes,
            reusableDelayDrillSeconds: nil,
            suggestedReefedCentimeters: nil
        )
    }

    static func tuningCurve(
        flights: [Flight],
        rocket: Rocket,
        selectedMotor: MotorSpec,
        weather: Weather,
        targetHeights: [Double],
        targetFlightTimeRange: ClosedRange<Double>? = nil,
        isReloadableMotor: Bool? = nil
    ) -> [HeightTuningPoint] {
        targetHeights.map { target in
            let result = optimizeForTarget(
                flights: flights,
                rocket: rocket,
                selectedMotor: selectedMotor,
                weather: weather,
                targetAltitudeFeet: target,
                targetFlightTimeRange: targetFlightTimeRange,
                isReloadableMotor: isReloadableMotor ?? selectedMotor.reloadable
            )
            return HeightTuningPoint(
                targetAltitudeFeet: target,
                suggestedMassGrams: result.suggestedMassGrams,
                predictedAltitudeFeet: result.suggestedAltitudeFeet,
                confidence: result.confidence,
                reusableDelayDrillSeconds: result.reusableDelayDrillSeconds
            )
        }
    }

    private static func inputFromFlight(_ flight: Flight) -> PredictionInput {
        PredictionInput(
            motorType: flight.motorType,
            motorDesignation: flight.motorDesignation,
            rocketMassGrams: flight.rocketMassGrams,
            temperatureF: flight.weather.temperatureF,
            windMPH: flight.weather.windMPH,
            humidityPercent: flight.weather.humidityPercent,
            rocketMaterial: .cardboard,
            parachuteSizeInches: flight.parachuteSizeInches,
            rocketHeightMillimeters: 700,
            rocketWidthMillimeters: 66
        )
    }

    private static func trainingFlights(from flights: [Flight], input: PredictionInput? = nil) -> [Flight] {
        var output = flights
        for flight in flights {
            guard flight.measuredAltitudeFeet.isFinite else { continue }
            let videoSignals = flight.attachments.filter {
                $0.kind == .video && (($0.videoModelConfidence ?? 0) >= 0.55)
            }
            if let input {
                let relevanceBoost = sameDayRelevanceBoost(for: flight, input: input)
                if relevanceBoost > 0 {
                    output.append(contentsOf: Array(repeating: flight, count: relevanceBoost))
                }
            }
            guard let strongestSignal = videoSignals.max(by: { ($0.videoModelConfidence ?? 0) < ($1.videoModelConfidence ?? 0) }) else {
                continue
            }

            var analyzedFlight = flight
            if analyzedFlight.flightTimeSeconds == nil,
               let estimatedTime = strongestSignal.videoEstimatedFlightTimeSeconds,
               estimatedTime.isFinite {
                analyzedFlight.flightTimeSeconds = estimatedTime
            }

            // Analyzed launch videos make a flight more trustworthy because timing and flight events
            // were reviewed instead of relying only on manual entry. Duplicate once, not many times,
            // so video analysis helps the weight model without overpowering real flight logs.
            output.append(analyzedFlight)
        }
        return output
    }

    private static func sameDayRelevanceBoost(for flight: Flight, input: PredictionInput) -> Int {
        var boost = 0
        if flight.motorDesignation == input.motorDesignation {
            boost += 2
        } else if flight.motorType == input.motorType {
            boost += 1
        }

        let weatherDistance =
            abs(flight.weather.temperatureF - input.temperatureF) / 18
            + abs(flight.weather.windMPH - input.windMPH) / 6
            + abs(flight.weather.humidityPercent - input.humidityPercent) / 35
        if weatherDistance <= 1.0 {
            boost += 2
        } else if weatherDistance <= 2.0 {
            boost += 1
        }

        let massDelta = abs(flight.rocketMassGrams - input.rocketMassGrams)
        if massDelta <= 25 {
            boost += 2
        } else if massDelta <= 70 {
            boost += 1
        }

        let hoursOld = abs(flight.flownAt.timeIntervalSinceNow) / 3_600
        if hoursOld <= 36 {
            boost += 2
        } else if hoursOld <= 24 * 21 {
            boost += 1
        }

        if flight.attachments.contains(where: { ($0.videoModelConfidence ?? 0) >= 0.55 }) {
            boost += 1
        }
        if flight.flightTimeSeconds != nil {
            boost += 1
        }

        return min(boost, 7)
    }

    private static func rawFeatureVector(_ input: PredictionInput) -> [Double] {
        [
            input.rocketMassGrams,
            input.motorType.impulseScore,
            motorImpulse(for: input.motorDesignation),
            input.temperatureF,
            input.windMPH,
            input.humidityPercent,
            input.rocketMaterial.dragFactor,
            input.parachuteSizeInches,
            input.rocketHeightMillimeters,
            input.rocketWidthMillimeters
        ]
    }

    private static func physicsPriorAltitude(for input: PredictionInput) -> Double {
        let impulse = motorImpulse(for: input.motorDesignation)
        let massPenalty = (input.rocketMassGrams - 650) * 1.25
        let impulseBoost = (impulse - 45) * 3.5
        let windPenalty = input.windMPH * 2.2
        let densityLift = (input.temperatureF - 70) * 0.9 - (input.humidityPercent - 45) * 0.25
        let dragPenalty = (input.rocketMaterial.dragFactor - 1) * 120
            + max(0, input.rocketWidthMillimeters - 55) * 1.4
            + max(0, input.parachuteSizeInches - 18) * 1.2
            + max(0, input.rocketHeightMillimeters - 700) * 0.025
        return sanitizedAltitude(760 + impulseBoost - massPenalty - windPenalty + densityLift - dragPenalty)
    }

    private static func sanitizedAltitude(_ value: Double) -> Double {
        guard value.isFinite else { return 750 }
        return min(max(value, 50), 4_000)
    }

    private static func nearbyMotor(for designation: String, shouldIncrease: Bool) -> MotorSpec? {
        guard let current = MotorCatalog.motor(named: designation) else { return nil }
        let sorted = MotorCatalog.competitionMotors.sorted { $0.totalImpulseNS < $1.totalImpulseNS }
        guard let index = sorted.firstIndex(of: current) else { return nil }
        let nextIndex = shouldIncrease ? min(index + 1, sorted.count - 1) : max(index - 1, 0)
        guard nextIndex != index else { return nil }
        return sorted[nextIndex]
    }

    private static func bestMassFromModel(flights: [Flight], input: PredictionInput, targetAltitude: Double) -> Double {
        var bestMass = input.rocketMassGrams
        var bestError = Double.greatestFiniteMagnitude
        let lowerBound = max(1, input.rocketMassGrams - 800)
        let upperBound = max(input.rocketMassGrams + 800, input.rocketMassGrams * 2.5)
        for mass in stride(from: lowerBound, through: upperBound, by: 25) {
            var candidate = input
            candidate.rocketMassGrams = mass
            let prediction = predict(flights: flights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitude)
            if error < bestError {
                bestError = error
                bestMass = mass
            }
        }
        return bestMass
    }

    private static func bestMassSearchRange(for rocket: Rocket, currentMass: Double) -> ClosedRange<Double> {
        let lowerBound = max(1, min(rocket.dryMassGrams * 0.45, currentMass - 1_200))
        let upperBound = max(currentMass + 1_800, currentMass * 3.2, rocket.dryMassGrams + 2_000)
        return lowerBound...upperBound
    }

    private static func motorRecommendation(flights: [Flight], input: PredictionInput, targetAltitude: Double) -> Recommendation? {
        let grouped = Dictionary(grouping: flights) { $0.motorDesignation }
            .filter { $0.value.count >= 2 }
        guard grouped.count >= 2 else { return nil }

        let currentMass = input.rocketMassGrams
        let candidates = grouped.compactMap { designation, motorFlights -> (String, Double, Double)? in
            guard let motor = MotorCatalog.motor(named: designation) else { return nil }
            var candidate = input
            candidate.motorDesignation = designation
            candidate.motorType = motor.motorClass
            candidate.rocketMassGrams = currentMass
            let predicted = predict(flights: motorFlights, input: candidate).altitudeFeet
            return (designation, predicted, abs(predicted - targetAltitude))
        }
        guard let best = candidates.min(by: { $0.2 < $1.2 }) else { return nil }
        let currentError = abs(predict(flights: flights, input: input).altitudeFeet - targetAltitude)
        guard best.0 != input.motorDesignation, best.2 + 8 < currentError else { return nil }
        return Recommendation(
            title: "Data favors \(best.0)",
            detail: "From logged flights using motors you have tested, \(best.0) is currently closest to \(Int(targetAltitude)) ft with a predicted miss of about \(Int(best.2)) ft.",
            priority: best.2 < 25 ? .medium : .low
        )
    }

    private static func timingRecommendation(flights: [Flight], targetRange: ClosedRange<Double>) -> Recommendation? {
        let timedFlights = flights.filter { $0.flightTimeSeconds != nil }
        guard timedFlights.count >= 3 else { return nil }
        let averageTime = timedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(timedFlights.count)
        if targetRange.contains(averageTime) {
            return Recommendation(
                title: "Timing is in range",
                detail: "Your logged flights average \(String(format: "%.1f", averageTime)) s, inside the \(Int(targetRange.lowerBound))-\(Int(targetRange.upperBound)) s window. Keep parachute and delay close to the current setup.",
                priority: .low
            )
        }

        let targetMid = (targetRange.lowerBound + targetRange.upperBound) / 2
        let timeDelta = targetMid - averageTime
        let reefedFlights = timedFlights.filter { $0.parachuteReefedCentimeters != nil }
        let reefSlope = empiricalSlope(
            flights: reefedFlights,
            x: { $0.parachuteReefedCentimeters ?? 0 },
            y: { $0.flightTimeSeconds ?? averageTime }
        )
        if let reefSlope, abs(reefSlope) > 0.03 {
            let currentReef = reefedFlights.compactMap(\.parachuteReefedCentimeters).reduce(0, +) / Double(reefedFlights.count)
            let reefChange = timeDelta / reefSlope
            let suggestedReef = max(0, currentReef + reefChange)
            return Recommendation(
                title: "Tune parachute reefing",
                detail: "Your logs show about \(String(format: "%.2f", reefSlope)) s per cm of reefing. Try about \(String(format: "%.1f", suggestedReef)) cm reefed to move toward \(String(format: "%.1f", targetMid)) s.",
                priority: .medium
            )
        }

        let chuteSlope = empiricalSlope(
            flights: timedFlights,
            x: \.parachuteSizeInches,
            y: { $0.flightTimeSeconds ?? averageTime }
        )
        if let chuteSlope, abs(chuteSlope) > 0.05 {
            let chuteChange = min(max(timeDelta / chuteSlope, -8), 8)
            return Recommendation(
                title: chuteChange > 0 ? "Use more chute area" : "Use less chute area",
                detail: "Your logs show about \(String(format: "%.1f", abs(chuteSlope))) s per inch of parachute. Change chute size by about \(String(format: "%.1f", chuteChange)) in to move toward \(String(format: "%.1f", targetMid)) s.",
                priority: .medium
            )
        }

        return Recommendation(
            title: averageTime < targetRange.lowerBound ? "Increase flight time" : "Reduce flight time",
            detail: "Your logged flights average \(String(format: "%.1f", averageTime)) s. Add timed flights with reefed length in centimeters so the app can calculate the exact reefing adjustment.",
            priority: .medium
        )
    }

    private static func recommendedReefedCentimeters(
        flights: [Flight],
        targetRange: ClosedRange<Double>?,
        estimatedFlightTime: Double
    ) -> Double? {
        guard let targetRange else { return nil }
        let timedFlights = flights.filter { $0.flightTimeSeconds != nil && $0.parachuteReefedCentimeters != nil }
        guard timedFlights.count >= 3 else { return nil }
        let averageTime = timedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(timedFlights.count)
        let targetMid = (targetRange.lowerBound + targetRange.upperBound) / 2
        guard let reefSlope = empiricalSlope(
            flights: timedFlights,
            x: { $0.parachuteReefedCentimeters ?? 0 },
            y: { $0.flightTimeSeconds ?? averageTime }
        ), abs(reefSlope) > 0.03 else {
            return nil
        }
        let currentReef = timedFlights.compactMap(\.parachuteReefedCentimeters).reduce(0, +) / Double(timedFlights.count)
        let currentTime = averageTime.isFinite ? averageTime : estimatedFlightTime
        let reefChange = (targetMid - currentTime) / reefSlope
        return max(0, currentReef + reefChange)
    }

    private static func empiricalSlope(
        flights: [Flight],
        x: (Flight) -> Double,
        y: (Flight) -> Double
    ) -> Double? {
        let points = flights
            .map { (x($0), y($0)) }
            .filter { $0.0.isFinite && $0.1.isFinite }
        guard points.count >= 3 else { return nil }
        let meanX = points.map(\.0).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.1).reduce(0, +) / Double(points.count)
        let numerator = points.reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
        let denominator = points.reduce(0) { $0 + pow($1.0 - meanX, 2) }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private static func motorImpulse(for designation: String) -> Double {
        MotorCatalog.motor(named: designation)?.totalImpulseNS ?? 35
    }

    private static func estimatedFlightTimeSeconds(rocket: Rocket, massGrams: Double, weather: Weather) -> Double {
        let base = 31.0
        let chuteEffect = rocket.parachuteSizeInches * 0.34
        let massEffect = (massGrams - rocket.dryMassGrams) * 0.012
        let widthEffect = rocket.widthMillimeters * 0.03
        let windPenalty = weather.windMPH * 0.07
        return max(10, base + chuteEffect + massEffect + widthEffect - windPenalty)
    }

    private static func recommendedDelayAdjustmentSeconds(
        estimatedFlightTime: Double,
        targetRange: ClosedRange<Double>
    ) -> Double {
        let targetMid = (targetRange.lowerBound + targetRange.upperBound) / 2
        let difference = targetMid - estimatedFlightTime
        return (difference * 0.6 * 10).rounded() / 10
    }

    private static func dot(_ left: [Double], _ right: [Double]) -> Double {
        zip(left, right).reduce(0) { total, pair in
            total + pair.0 * pair.1
        }
    }

    private static func solveLinearSystem(matrix: [[Double]], values: [Double]) -> [Double] {
        let n = values.count
        var augmented = matrix.enumerated().map { index, row in row + [values[index]] }

        for pivot in 0..<n {
            var maxRow = pivot
            for row in (pivot + 1)..<n where abs(augmented[row][pivot]) > abs(augmented[maxRow][pivot]) {
                maxRow = row
            }

            augmented.swapAt(pivot, maxRow)
            let divisor = augmented[pivot][pivot] == 0 ? 1e-9 : augmented[pivot][pivot]
            for column in pivot...n {
                augmented[pivot][column] /= divisor
            }

            for row in 0..<n where row != pivot {
                let factor = augmented[row][pivot]
                for column in pivot...n {
                    augmented[row][column] -= factor * augmented[pivot][column]
                }
            }
        }

        return augmented.map { $0[n] }
    }
}

private struct FeatureNormalizer {
    private let means: [Double]
    private let scales: [Double]

    init(rows: [[Double]]) {
        let width = rows.first?.count ?? 0
        let computedMeans = (0..<width).map { column in
            rows.map { $0[column] }.reduce(0, +) / Double(max(rows.count, 1))
        }
        let computedScales = (0..<width).map { column in
            let mean = computedMeans[column]
            let variance = rows.map { pow($0[column] - mean, 2) }.reduce(0, +) / Double(max(rows.count, 1))
            return max(sqrt(variance), 1)
        }
        means = computedMeans
        scales = computedScales
    }

    func normalized(_ row: [Double]) -> [Double] {
        [1] + row.enumerated().map { index, value in
            (value - means[index]) / scales[index]
        }
    }
}
