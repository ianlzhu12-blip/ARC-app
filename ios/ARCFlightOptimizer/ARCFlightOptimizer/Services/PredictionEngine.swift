import Foundation

enum PredictionEngine {
    static func predict(flights: [Flight], input: PredictionInput) -> Prediction {
        let usableFlights = robustTrainingFlights(
            from: trainingFlights(from: flights, input: input).filter { $0.measuredAltitudeFeet.isFinite },
            input: input
        )
        let priorAltitude = physicsPriorAltitude(for: input)
        let localEstimate = localAltitudeEstimate(flights: usableFlights, input: input)

        guard usableFlights.count >= 4 else {
            let average = usableFlights.isEmpty
                ? priorAltitude
                : usableFlights.map(\.measuredAltitudeFeet).reduce(0, +) / Double(usableFlights.count)
            let blended = usableFlights.isEmpty
                ? priorAltitude
                : priorAltitude * 0.55 + average * 0.45
            let altitude: Double
            let confidence: Double
            if let localEstimate {
                let localTrust = min(0.82, max(0.45, localEstimate.confidence))
                altitude = sanitizedAltitude(localEstimate.altitudeFeet * localTrust + blended * (1 - localTrust))
                confidence = max(min(0.62, localEstimate.confidence), min(0.45, Double(usableFlights.count) * 0.12))
            } else {
                altitude = sanitizedAltitude(blended)
                confidence = min(0.45, Double(usableFlights.count) * 0.12)
            }
            return Prediction(
                altitudeFeet: altitude.rounded(),
                confidence: confidence,
                method: "baseline"
            )
        }

        let rawFeatures = usableFlights.map { rawFeatureVector(inputFromFlight($0)) }
        let normalizer = FeatureNormalizer(rows: rawFeatures)
        let features = rawFeatures.map { normalizer.normalized($0) }
        let queryFeatures = normalizer.normalized(rawFeatureVector(input))

        let targets = usableFlights.map(\.measuredAltitudeFeet)
        let sampleWeights = usableFlights.map { similarityWeight(for: $0, input: input) }
        let width = features[0].count
        var xtx = Array(repeating: Array(repeating: 0.0, count: width), count: width)
        var xty = Array(repeating: 0.0, count: width)

        // Ridge regression keeps field predictions stable with small, noisy ARC launch datasets.
        // Inputs include motor impulse, mass, weather, and key airframe variables.
        // The goal is an explainable field model rather than a black-box predictor.
        for row in 0..<features.count {
            let weight = sampleWeights[row]
            for i in 0..<width {
                xty[i] += features[row][i] * targets[row] * weight
                for j in 0..<width {
                    xtx[i][j] += features[row][i] * features[row][j] * weight
                }
            }
        }

        // Small field datasets can be noisy; ridge strength is lowered as useful data grows.
        let ridge = max(0.08, 0.42 - Double(min(usableFlights.count, 18)) * 0.015)
        for i in 1..<width {
            xtx[i][i] += ridge
        }

        let weights = solveLinearSystem(matrix: xtx, values: xty)
        let regressionAltitude = dot(queryFeatures, weights)
        let neighborCorrection = nearestNeighborResidualCorrection(
            flights: usableFlights,
            features: features,
            targets: targets,
            weights: weights,
            queryFeatures: queryFeatures,
            input: input
        )
        let calibratedAltitude = regressionAltitude + neighborCorrection
        let trust = modelTrust(flightCount: usableFlights.count, input: input, flights: usableFlights)
        let modelAltitude = sanitizedAltitude(calibratedAltitude * trust + priorAltitude * (1 - trust))
        let altitude: Double
        if let localEstimate {
            let localTrust = min(0.84, max(0.22, localEstimate.confidence))
            altitude = sanitizedAltitude(localEstimate.altitudeFeet * localTrust + modelAltitude * (1 - localTrust))
        } else {
            altitude = modelAltitude
        }
        let meanError = weightedMeanAbsoluteError(
            features: features,
            targets: targets,
            weights: weights,
            sampleWeights: sampleWeights
        )
        let neighborBonus = abs(neighborCorrection) > 0 ? 0.04 : 0
        let localBonus = localEstimate.map { min(0.09, $0.confidence * 0.08) } ?? 0
        let confidence = confidenceScore(
            flightCount: usableFlights.count,
            meanError: meanError,
            trust: trust,
            neighborBonus: neighborBonus + localBonus
        )

        return Prediction(
            altitudeFeet: altitude.rounded(),
            confidence: confidence,
            method: "regression"
        )
    }

    static func recommendations(
        flights: [Flight],
        input: PredictionInput,
        targetAltitude: Double,
        targetFlightTimeRange: ClosedRange<Double>? = nil
    ) -> [Recommendation] {
        let groupedFlights = targetGroupedFlights(from: flights, targetAltitude: targetAltitude)
        let usableFlights = trainingFlights(from: groupedFlights, input: input).filter { $0.measuredAltitudeFeet.isFinite }
        let current = predict(flights: usableFlights, input: input)
        let delta = targetAltitude - current.altitudeFeet

        var output: [Recommendation] = []
        if abs(delta) <= 8 {
            output.append(
                Recommendation(
                    title: "Hold this setup",
                    detail: "The current model predicts \(Int(current.altitudeFeet)) ft, within \(Int(abs(delta))) ft of the \(Int(targetAltitude)) ft target. Keep the mass, motor, and recovery setup steady and log another repeat flight.",
                    priority: .low
                )
            )
        } else {
            let slope = empiricalSlope(
                flights: usableFlights.filter { $0.motorDesignation == input.motorDesignation },
                x: \.rocketMassGrams,
                y: \.measuredAltitudeFeet
            ) ?? empiricalSlope(flights: usableFlights, x: \.rocketMassGrams, y: \.measuredAltitudeFeet)

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
        }

        if let targetFlightTimeRange {
            if let timing = timingRecommendation(
                flights: usableFlights,
                targetRange: targetFlightTimeRange,
                currentWindMPH: input.windMPH
            ) {
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
        let targetGroupedFlights = targetGroupedFlights(from: flights, targetAltitude: targetAltitudeFeet)
        let exactTargetGroup = wantedAltitudeGroup(from: flights, targetAltitude: targetAltitudeFeet)
        let currentMass = baselineReadyMass(for: rocket, selectedMotor: selectedMotor, flights: flights)
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
        var bestPrediction = predict(flights: targetGroupedFlights, input: baseInput)
        var bestError = abs(bestPrediction.altitudeFeet - targetAltitudeFeet)
        var bestScore = bestError + massEvidencePenalty(
            massGrams: bestMass,
            flights: targetGroupedFlights,
            selectedMotor: selectedMotor
        )

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
            let prediction = predict(flights: targetGroupedFlights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitudeFeet)
            let score = error + massEvidencePenalty(
                massGrams: step,
                flights: targetGroupedFlights,
                selectedMotor: selectedMotor
            )
            if score < bestScore {
                bestMass = step
                bestPrediction = prediction
                bestError = error
                bestScore = score
            }
        }

        for step in stride(from: max(coarseSearch.lowerBound, bestMass - 35), through: min(coarseSearch.upperBound, bestMass + 35), by: 5) {
            var candidate = baseInput
            candidate.rocketMassGrams = step
            let prediction = predict(flights: targetGroupedFlights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitudeFeet)
            let score = error + massEvidencePenalty(
                massGrams: step,
                flights: targetGroupedFlights,
                selectedMotor: selectedMotor
            )
            if score < bestScore {
                bestMass = step
                bestPrediction = prediction
                bestError = error
                bestScore = score
            }
        }

        for step in stride(from: max(coarseSearch.lowerBound, bestMass - 8), through: min(coarseSearch.upperBound, bestMass + 8), by: 1) {
            var candidate = baseInput
            candidate.rocketMassGrams = step
            let prediction = predict(flights: targetGroupedFlights, input: candidate)
            let error = abs(prediction.altitudeFeet - targetAltitudeFeet)
            let score = error + massEvidencePenalty(
                massGrams: step,
                flights: targetGroupedFlights,
                selectedMotor: selectedMotor
            )
            if score < bestScore {
                bestMass = step
                bestPrediction = prediction
                bestError = error
                bestScore = score
            }
        }

        let empiricalAnchor = empiricalMassAnchor(
            flights: flights,
            rocket: rocket,
            selectedMotor: selectedMotor,
            weather: weather,
            targetAltitudeFeet: targetAltitudeFeet
        )
        if let empiricalAnchor,
           empiricalAnchor.nearestMissFeet <= max(12, bestError + 18) {
            bestMass = empiricalAnchor.massGrams
            bestPrediction = Prediction(
                altitudeFeet: empiricalAnchor.observedAltitudeFeet.rounded(),
                confidence: max(bestPrediction.confidence, empiricalAnchor.confidence),
                method: "regression"
            )
            bestError = abs(empiricalAnchor.observedAltitudeFeet - targetAltitudeFeet)
        }

        let estimatedFlightTime = estimatedFlightTimeSeconds(rocket: rocket, massGrams: bestMass, weather: weather)
        let reloadable = isReloadableMotor ?? selectedMotor.reloadable
        let reefSuggestion = recommendedReefedCentimeters(
            flights: targetGroupedFlights,
            targetRange: targetFlightTimeRange,
            estimatedFlightTime: estimatedFlightTime,
            currentWindMPH: weather.windMPH
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
            "Flights with the same wanted altitude are grouped and weighted more heavily before calculating mass and reefing.",
            "Mass recommendations prefer weights close to real logged flights unless a farther mass clearly predicts better.",
            "Suggested mass is relative to an estimated ready-to-fly baseline of about \(Int(currentMass)) g."
        ]
        if exactTargetGroup.count >= 2 {
            notes.append("Using \(exactTargetGroup.count) logged flight\(exactTargetGroup.count == 1 ? "" : "s") from the \(Int(targetAltitudeFeet.rounded())) ft wanted-altitude group as the strongest calibration set.")
        }
        if let empiricalAnchor,
           abs(empiricalAnchor.massGrams - bestMass) <= 0.1 {
            notes.append("Closest real flight data found \(Int(empiricalAnchor.observedAltitudeFeet.rounded())) ft at \(Int(empiricalAnchor.massGrams.rounded())) g, so the optimizer favored that proven setup over the generic baseline.")
        }
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
            notes.append("Based on logged flight-time, wind speed, and reefing data, try about \(String(format: "%.1f", reefSuggestion)) cm of parachute reefing for the time window.")
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
        let currentMass = baselineReadyMass(for: rocket, selectedMotor: selectedMotor, flights: flights)
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

    private static func targetGroupedFlights(from flights: [Flight], targetAltitude: Double) -> [Flight] {
        let group = wantedAltitudeGroup(from: flights, targetAltitude: targetAltitude)
        guard group.count >= 2 else { return flights }

        var output = flights
        let repeatCount = group.count >= 5 ? 3 : 2
        for _ in 0..<repeatCount {
            output.append(contentsOf: group)
        }
        return output
    }

    private static func wantedAltitudeGroup(from flights: [Flight], targetAltitude: Double) -> [Flight] {
        let roundedTarget = targetAltitude.rounded()
        return flights.filter { flight in
            guard let wanted = flight.targetAltitudeFeet, wanted.isFinite else { return false }
            return abs(wanted.rounded() - roundedTarget) <= 1
        }
    }

    private static func robustTrainingFlights(from flights: [Flight], input: PredictionInput) -> [Flight] {
        let finiteFlights = flights.filter {
            $0.measuredAltitudeFeet.isFinite &&
            $0.rocketMassGrams.isFinite &&
            !$0.excludedFromAI
        }
        guard finiteFlights.count >= 7 else { return finiteFlights }

        let altitudes = finiteFlights.map(\.measuredAltitudeFeet)
        let medianAltitude = median(altitudes)
        let deviations = altitudes.map { abs($0 - medianAltitude) }
        let medianDeviation = max(median(deviations), 35)
        let physicsPrior = physicsPriorAltitude(for: input)

        let rangeCheckedFlights = finiteFlights.filter { flight in
            let robustZ = abs(flight.measuredAltitudeFeet - medianAltitude) / medianDeviation
            let priorMiss = abs(flight.measuredAltitudeFeet - physicsPrior)
            if robustZ > 4.8 && priorMiss > 450 {
                return false
            }
            if flight.measuredAltitudeFeet < 50 || flight.measuredAltitudeFeet > 4_000 {
                return false
            }
            return true
        }

        return patternConsistentFlights(rangeCheckedFlights)
    }

    private static func patternConsistentFlights(_ flights: [Flight]) -> [Flight] {
        guard flights.count >= 7 else { return flights }

        var uniqueFlights: [UUID: Flight] = [:]
        for flight in flights where uniqueFlights[flight.id] == nil {
            uniqueFlights[flight.id] = flight
        }
        let uniqueValues = Array(uniqueFlights.values)
        guard uniqueValues.count >= 7 else { return flights }

        let acceptedIDs = Set(uniqueValues.compactMap { flight -> UUID? in
            if isSameMassOutlier(flight, in: uniqueValues) {
                return nil
            }
            if isSameAltitudeOutlier(flight, in: uniqueValues) {
                return nil
            }
            return flight.id
        })

        guard acceptedIDs.count >= max(5, uniqueValues.count / 2) else { return flights }
        return flights.filter { acceptedIDs.contains($0.id) }
    }

    private static func isSameMassOutlier(_ flight: Flight, in flights: [Flight]) -> Bool {
        let neighbors = flights.filter {
            $0.id != flight.id &&
            $0.motorDesignation == flight.motorDesignation &&
            abs($0.rocketMassGrams - flight.rocketMassGrams) <= 3
        }
        guard neighbors.count >= 2 else { return false }

        let expectedAltitude = median(neighbors.map(\.measuredAltitudeFeet))
        let allowedMiss = max(90, expectedAltitude * 0.12)
        return abs(flight.measuredAltitudeFeet - expectedAltitude) > allowedMiss
    }

    private static func isSameAltitudeOutlier(_ flight: Flight, in flights: [Flight]) -> Bool {
        let neighbors = flights.filter {
            $0.id != flight.id &&
            $0.motorDesignation == flight.motorDesignation &&
            abs($0.measuredAltitudeFeet - flight.measuredAltitudeFeet) <= 15
        }
        guard neighbors.count >= 2 else { return false }

        let expectedMass = median(neighbors.map(\.rocketMassGrams))
        let allowedMiss = max(80, expectedMass * 0.14)
        return abs(flight.rocketMassGrams - expectedMass) > allowedMiss
    }

    private static func similarityWeight(for flight: Flight, input: PredictionInput) -> Double {
        var weight = 1.0
        if flight.motorDesignation == input.motorDesignation {
            weight += 2.8
        } else if flight.motorType == input.motorType {
            weight += 1.1
        }

        let massDistance = abs(flight.rocketMassGrams - input.rocketMassGrams)
        weight += max(0, 2.0 - massDistance / 55)

        let weatherDistance =
            abs(flight.weather.temperatureF - input.temperatureF) / 22
            + abs(flight.weather.windMPH - input.windMPH) / 7
            + abs(flight.weather.humidityPercent - input.humidityPercent) / 40
        weight += max(0, 1.6 - weatherDistance * 0.45)

        if let target = flight.targetAltitudeFeet, target.isFinite {
            let predictedSetupAltitude = physicsPriorAltitude(for: input)
            let targetDistance = abs(target - predictedSetupAltitude)
            weight += max(0, 1.0 - targetDistance / 250)
        }
        if flight.attachments.contains(where: { ($0.videoModelConfidence ?? 0) >= 0.65 }) {
            weight += 0.55
        }
        if flight.flightTimeSeconds != nil {
            weight += 0.25
        }

        return min(max(weight, 0.35), 8.0)
    }

    private static func nearestNeighborResidualCorrection(
        flights: [Flight],
        features: [[Double]],
        targets: [Double],
        weights: [Double],
        queryFeatures: [Double],
        input: PredictionInput
    ) -> Double {
        guard flights.count >= 5 else { return 0 }

        let residuals = zip(features, targets).map { row, actual in
            actual - dot(row, weights)
        }
        let neighbors = features.indices.map { index -> (distance: Double, residual: Double, reliability: Double) in
            let distance = euclideanDistance(features[index], queryFeatures)
            let reliability = similarityWeight(for: flights[index], input: input)
            return (distance, residuals[index], reliability)
        }
        .sorted { $0.distance < $1.distance }
        .prefix(min(6, max(3, flights.count / 2)))

        var weightedResidual = 0.0
        var totalWeight = 0.0
        for neighbor in neighbors {
            let weight = neighbor.reliability / max(0.25, neighbor.distance)
            weightedResidual += neighbor.residual * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return 0 }
        return min(max(weightedResidual / totalWeight, -140), 140)
    }

    private struct LocalAltitudeEstimate {
        var altitudeFeet: Double
        var confidence: Double
        var sampleCount: Int
        var nearestDistance: Double
    }

    private static func localAltitudeEstimate(flights: [Flight], input: PredictionInput) -> LocalAltitudeEstimate? {
        var uniqueFlights: [UUID: Flight] = [:]
        for flight in flights where uniqueFlights[flight.id] == nil {
            uniqueFlights[flight.id] = flight
        }

        let scored = uniqueFlights.values.compactMap { flight -> (flight: Flight, distance: Double, weight: Double)? in
            guard
                flight.measuredAltitudeFeet.isFinite,
                flight.rocketMassGrams.isFinite,
                !flight.excludedFromAI
            else {
                return nil
            }

            let motorPenalty: Double
            if flight.motorDesignation == input.motorDesignation {
                motorPenalty = 0
            } else if flight.motorType == input.motorType {
                motorPenalty = 0.9
            } else {
                motorPenalty = 2.4
            }

            let massTerm = abs(flight.rocketMassGrams - input.rocketMassGrams) / 32
            let windTerm = abs(flight.weather.windMPH - input.windMPH) / 6
            let temperatureTerm = abs(flight.weather.temperatureF - input.temperatureF) / 20
            let humidityTerm = abs(flight.weather.humidityPercent - input.humidityPercent) / 42
            let parachuteTerm = abs(flight.parachuteSizeInches - input.parachuteSizeInches) / 8
            let distance = sqrt(
                massTerm * massTerm +
                windTerm * windTerm +
                temperatureTerm * temperatureTerm +
                humidityTerm * humidityTerm +
                parachuteTerm * parachuteTerm +
                motorPenalty * motorPenalty
            )
            guard distance <= 4.2 else { return nil }

            var reliability = 1.0
            if flight.motorDesignation == input.motorDesignation {
                reliability += 1.0
            }
            if abs(flight.rocketMassGrams - input.rocketMassGrams) <= 5 {
                reliability += 0.75
            }
            if abs(flight.weather.windMPH - input.windMPH) <= 2 {
                reliability += 0.35
            }
            if flight.attachments.contains(where: { ($0.videoModelConfidence ?? 0) >= 0.55 }) {
                reliability += 0.2
            }

            let weight = reliability / pow(max(0.22, distance), 2)
            return (flight, distance, weight)
        }
        .sorted { $0.distance < $1.distance }

        guard let nearest = scored.first else { return nil }
        let neighbors = Array(scored.prefix(min(8, max(3, scored.count))))
        let totalWeight = neighbors.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }

        let altitude = neighbors.reduce(0) { total, neighbor in
            total + neighbor.flight.measuredAltitudeFeet * neighbor.weight
        } / totalWeight
        let exactMotorCount = neighbors.filter { $0.flight.motorDesignation == input.motorDesignation }.count
        let nearestBoost = max(0, (3.4 - nearest.distance) / 3.4) * 0.36
        let sampleBoost = min(0.14, Double(neighbors.count) * 0.025)
        let motorBoost = exactMotorCount > 0 ? 0.08 : 0
        let confidence = min(0.84, max(0.28, 0.24 + nearestBoost + sampleBoost + motorBoost))
        return LocalAltitudeEstimate(
            altitudeFeet: altitude,
            confidence: confidence,
            sampleCount: neighbors.count,
            nearestDistance: nearest.distance
        )
    }

    private static func weightedMeanAbsoluteError(
        features: [[Double]],
        targets: [Double],
        weights: [Double],
        sampleWeights: [Double]
    ) -> Double {
        var error = 0.0
        var totalWeight = 0.0
        for index in features.indices {
            let sampleWeight = sampleWeights[index]
            error += abs(dot(features[index], weights) - targets[index]) * sampleWeight
            totalWeight += sampleWeight
        }
        return totalWeight > 0 ? error / totalWeight : 160
    }

    private static func modelTrust(flightCount: Int, input: PredictionInput, flights: [Flight]) -> Double {
        let exactMotorCount = flights.filter { $0.motorDesignation == input.motorDesignation }.count
        let nearMassCount = flights.filter { abs($0.rocketMassGrams - input.rocketMassGrams) <= 85 }.count
        var trust = 0.48 + Double(min(flightCount, 18)) * 0.018
        trust += Double(min(exactMotorCount, 6)) * 0.025
        trust += Double(min(nearMassCount, 6)) * 0.015
        return min(max(trust, 0.50), 0.86)
    }

    private static func confidenceScore(
        flightCount: Int,
        meanError: Double,
        trust: Double,
        neighborBonus: Double
    ) -> Double {
        let dataScore = min(0.24, Double(flightCount) * 0.018)
        let errorScore = max(-0.35, min(0.22, (95 - meanError) / 240))
        return min(max(0.28 + dataScore + errorScore + trust * 0.28 + neighborBonus, 0.25), 0.94)
    }

    private static func euclideanDistance(_ left: [Double], _ right: [Double]) -> Double {
        sqrt(zip(left, right).reduce(0) { total, pair in
            total + pow(pair.0 - pair.1, 2)
        })
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
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

    private struct EmpiricalMassAnchor {
        var massGrams: Double
        var observedAltitudeFeet: Double
        var confidence: Double
        var sampleCount: Int
        var nearestMissFeet: Double
    }

    private static func baselineReadyMass(for rocket: Rocket, selectedMotor: MotorSpec, flights: [Flight]) -> Double {
        let usableFlights = flights
            .filter {
                !$0.excludedFromAI &&
                $0.rocketID == rocket.id &&
                $0.rocketMassGrams.isFinite &&
                $0.measuredAltitudeFeet.isFinite
            }
            .sorted { $0.flownAt > $1.flownAt }

        if let recentSameMotor = usableFlights.first(where: { $0.motorDesignation == selectedMotor.designation }) {
            return recentSameMotor.rocketMassGrams
        }
        if let recent = usableFlights.first {
            return recent.rocketMassGrams
        }
        return rocket.dryMassGrams + 90
    }

    private static func empiricalMassAnchor(
        flights: [Flight],
        rocket: Rocket,
        selectedMotor: MotorSpec,
        weather: Weather,
        targetAltitudeFeet: Double
    ) -> EmpiricalMassAnchor? {
        let sameRocketFlights = flights.filter {
            !$0.excludedFromAI &&
            $0.rocketID == rocket.id &&
            $0.rocketMassGrams.isFinite &&
            $0.measuredAltitudeFeet.isFinite &&
            (50...4_000).contains($0.measuredAltitudeFeet) &&
            (1...4_000).contains($0.rocketMassGrams)
        }
        guard !sameRocketFlights.isEmpty else { return nil }

        let sameMotorFlights = sameRocketFlights.filter { $0.motorDesignation == selectedMotor.designation }
        let candidateFlights = sameMotorFlights.isEmpty ? sameRocketFlights : sameMotorFlights
        let scored = candidateFlights
            .map { flight -> (flight: Flight, miss: Double, weight: Double) in
                let miss = abs(flight.measuredAltitudeFeet - targetAltitudeFeet)
                let windDistance = abs(flight.weather.windMPH - weather.windMPH)
                let temperatureDistance = abs(flight.weather.temperatureF - weather.temperatureF)
                let humidityDistance = abs(flight.weather.humidityPercent - weather.humidityPercent)
                var weight = 1 / pow(max(3, miss), 2)
                if flight.motorDesignation == selectedMotor.designation {
                    weight *= 1.8
                }
                weight *= max(0.45, 1.25 - windDistance / 18)
                weight *= max(0.60, 1.10 - temperatureDistance / 90)
                weight *= max(0.70, 1.05 - humidityDistance / 160)
                if flight.attachments.contains(where: { ($0.videoModelConfidence ?? 0) >= 0.55 }) {
                    weight *= 1.12
                }
                return (flight, miss, weight)
            }
            .sorted { left, right in
                if abs(left.miss - right.miss) < 0.1 {
                    return left.flight.flownAt > right.flight.flownAt
                }
                return left.miss < right.miss
            }

        guard let nearest = scored.first else { return nil }
        let closeEnoughFeet = max(30.0, targetAltitudeFeet * 0.045)
        guard nearest.miss <= closeEnoughFeet else { return nil }

        if nearest.miss <= 3 {
            return EmpiricalMassAnchor(
                massGrams: nearest.flight.rocketMassGrams,
                observedAltitudeFeet: nearest.flight.measuredAltitudeFeet,
                confidence: sameMotorFlights.isEmpty ? 0.68 : 0.82,
                sampleCount: 1,
                nearestMissFeet: nearest.miss
            )
        }

        let localMatches = Array(scored.prefix(8).filter { $0.miss <= closeEnoughFeet })
        let totalWeight = localMatches.map(\.weight).reduce(0, +)
        guard totalWeight > 0 else { return nil }
        let mass = localMatches.reduce(0) { $0 + $1.flight.rocketMassGrams * $1.weight } / totalWeight
        let altitude = localMatches.reduce(0) { $0 + $1.flight.measuredAltitudeFeet * $1.weight } / totalWeight
        let motorBonus = sameMotorFlights.isEmpty ? 0.0 : 0.08
        let confidence = min(0.88, 0.55 + Double(min(localMatches.count, 5)) * 0.045 + motorBonus)
        return EmpiricalMassAnchor(
            massGrams: mass,
            observedAltitudeFeet: altitude,
            confidence: confidence,
            sampleCount: localMatches.count,
            nearestMissFeet: nearest.miss
        )
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

    private static func massEvidencePenalty(
        massGrams: Double,
        flights: [Flight],
        selectedMotor: MotorSpec
    ) -> Double {
        let finiteFlights = flights.filter {
            !$0.excludedFromAI &&
            $0.rocketMassGrams.isFinite &&
            $0.measuredAltitudeFeet.isFinite
        }
        let sameMotorMasses = finiteFlights
            .filter { $0.motorDesignation == selectedMotor.designation }
            .map(\.rocketMassGrams)
        let masses = sameMotorMasses.isEmpty ? finiteFlights.map(\.rocketMassGrams) : sameMotorMasses
        guard masses.count >= 3 else { return 0 }

        let nearestMassDelta = masses.map { abs($0 - massGrams) }.min() ?? 0
        guard nearestMassDelta > 80 else { return 0 }
        return min(120, (nearestMassDelta - 80) * 0.12)
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

    private static func timingRecommendation(
        flights: [Flight],
        targetRange: ClosedRange<Double>,
        currentWindMPH: Double
    ) -> Recommendation? {
        let timedFlights = flights.filter { $0.flightTimeSeconds != nil }
        guard timedFlights.count >= 3 else { return nil }
        let averageTime = timedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(timedFlights.count)
        let targetMid = (targetRange.lowerBound + targetRange.upperBound) / 2
        let reefedTimedFlights = timedFlights.filter { $0.parachuteReefedCentimeters != nil }
        let averageReefedTime = reefedTimedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(max(reefedTimedFlights.count, 1))

        if let windModel = windAwareReefingModel(from: reefedTimedFlights),
           let suggestedReef = windModel.suggestedReef(targetSeconds: targetMid, currentWindMPH: currentWindMPH) {
            let predictedTime = windModel.predictedTime(reefedCentimeters: suggestedReef, windMPH: currentWindMPH)
            return Recommendation(
                title: "Tune reefing for wind",
                detail: "Your logs show flight time changes with both reefing and wind. For about \(String(format: "%.1f", currentWindMPH)) mph wind, try \(String(format: "%.1f", suggestedReef)) cm reefed; the model predicts about \(String(format: "%.1f", predictedTime)) s toward the \(String(format: "%.1f", targetMid)) s target.",
                priority: .medium
            )
        }

        if reefedTimedFlights.count >= 3, targetRange.contains(averageReefedTime) {
            return Recommendation(
                title: "Reefed timing is in range",
                detail: "Flights with logged reefing average \(String(format: "%.1f", averageReefedTime)) s, inside the \(Int(targetRange.lowerBound))-\(Int(targetRange.upperBound)) s window. Keep reefed centimeters close to the current setup.",
                priority: .low
            )
        }

        let reefSlope = empiricalSlope(
            flights: reefedTimedFlights,
            x: { $0.parachuteReefedCentimeters ?? 0 },
            y: { $0.flightTimeSeconds ?? averageReefedTime }
        )
        if let reefSlope, abs(reefSlope) > 0.03 {
            let timeDelta = targetMid - averageReefedTime
            let currentReef = reefedTimedFlights.compactMap(\.parachuteReefedCentimeters).reduce(0, +) / Double(reefedTimedFlights.count)
            let reefChange = timeDelta / reefSlope
            let suggestedReef = max(0, currentReef + reefChange)
            return Recommendation(
                title: "Tune parachute reefing",
                detail: "Your logs show about \(String(format: "%.2f", reefSlope)) s per cm of reefing. Try about \(String(format: "%.1f", suggestedReef)) cm reefed to move toward \(String(format: "%.1f", targetMid)) s.",
                priority: .medium
            )
        }

        if targetRange.contains(averageTime) {
            return Recommendation(
                title: "Timing is in range",
                detail: "Your timed flights average \(String(format: "%.1f", averageTime)) s, but reefing advice needs flights where centimeters reefed were logged.",
                priority: .low
            )
        }

        let chuteSlope = empiricalSlope(
            flights: timedFlights,
            x: \.parachuteSizeInches,
            y: { $0.flightTimeSeconds ?? averageTime }
        )
        if let chuteSlope, abs(chuteSlope) > 0.05 {
            let timeDelta = targetMid - averageTime
            let chuteChange = min(max(timeDelta / chuteSlope, -8), 8)
            return Recommendation(
                title: chuteChange > 0 ? "Use more chute area" : "Use less chute area",
                detail: "Your logs show about \(String(format: "%.1f", abs(chuteSlope))) s per inch of parachute. Change chute size by about \(String(format: "%.1f", chuteChange)) in to move toward \(String(format: "%.1f", targetMid)) s.",
                priority: .medium
            )
        }

        return Recommendation(
            title: averageTime < targetRange.lowerBound ? "Increase flight time" : "Reduce flight time",
            detail: "Your logged flights average \(String(format: "%.1f", averageTime)) s. Add timed flights with reefed length in centimeters so the app can calculate the exact reefing adjustment from reefed flights only.",
            priority: .medium
        )
    }

    private static func recommendedReefedCentimeters(
        flights: [Flight],
        targetRange: ClosedRange<Double>?,
        estimatedFlightTime: Double,
        currentWindMPH: Double
    ) -> Double? {
        guard let targetRange else { return nil }
        let timedFlights = flights.filter { $0.flightTimeSeconds != nil && $0.parachuteReefedCentimeters != nil }
        guard timedFlights.count >= 3 else { return nil }
        let averageTime = timedFlights.compactMap(\.flightTimeSeconds).reduce(0, +) / Double(timedFlights.count)
        let targetMid = (targetRange.lowerBound + targetRange.upperBound) / 2

        if let windModel = windAwareReefingModel(from: timedFlights),
           let windAwareReef = windModel.suggestedReef(targetSeconds: targetMid, currentWindMPH: currentWindMPH) {
            return windAwareReef
        }

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

    private struct WindAwareReefingModel {
        var averageReefCentimeters: Double
        var averageWindMPH: Double
        var averageFlightTimeSeconds: Double
        var reefSlopeSecondsPerCentimeter: Double
        var windSlopeSecondsPerMPH: Double
        var sampleCount: Int

        func predictedTime(reefedCentimeters: Double, windMPH: Double) -> Double {
            averageFlightTimeSeconds
                + reefSlopeSecondsPerCentimeter * (reefedCentimeters - averageReefCentimeters)
                + windSlopeSecondsPerMPH * (windMPH - averageWindMPH)
        }

        func suggestedReef(targetSeconds: Double, currentWindMPH: Double) -> Double? {
            guard abs(reefSlopeSecondsPerCentimeter) > 0.03 else { return nil }
            let windAdjustment = windSlopeSecondsPerMPH * (currentWindMPH - averageWindMPH)
            let reefDelta = (targetSeconds - averageFlightTimeSeconds - windAdjustment) / reefSlopeSecondsPerCentimeter
            let suggested = averageReefCentimeters + reefDelta
            guard suggested.isFinite else { return nil }
            return min(max(suggested, 0), 500)
        }
    }

    private static func windAwareReefingModel(from flights: [Flight]) -> WindAwareReefingModel? {
        let samples = flights.compactMap { flight -> (reef: Double, wind: Double, time: Double)? in
            guard
                let reef = flight.parachuteReefedCentimeters,
                let time = flight.flightTimeSeconds,
                reef.isFinite,
                time.isFinite,
                flight.weather.windMPH.isFinite,
                (0...500).contains(reef),
                (5...180).contains(time),
                (0...120).contains(flight.weather.windMPH)
            else {
                return nil
            }
            return (reef, flight.weather.windMPH, time)
        }
        guard samples.count >= 4 else { return nil }

        let averageReef = samples.map(\.reef).reduce(0, +) / Double(samples.count)
        let averageWind = samples.map(\.wind).reduce(0, +) / Double(samples.count)
        let averageTime = samples.map(\.time).reduce(0, +) / Double(samples.count)

        let centered = samples.map {
            (
                reef: $0.reef - averageReef,
                wind: $0.wind - averageWind,
                time: $0.time - averageTime
            )
        }
        let reefVariance = centered.reduce(0) { $0 + $1.reef * $1.reef }
        guard reefVariance > 0.5 else { return nil }

        let windVariance = centered.reduce(0) { $0 + $1.wind * $1.wind }
        let reefTime = centered.reduce(0) { $0 + $1.reef * $1.time }
        let ridge = max(0.35, Double(samples.count) * 0.04)

        let reefSlope: Double
        let windSlope: Double
        if windVariance > 0.5 {
            let reefWind = centered.reduce(0) { $0 + $1.reef * $1.wind }
            let windTime = centered.reduce(0) { $0 + $1.wind * $1.time }
            let matrix = [
                [reefVariance + ridge, reefWind],
                [reefWind, windVariance + ridge]
            ]
            let slopes = solveLinearSystem(matrix: matrix, values: [reefTime, windTime])
            reefSlope = slopes[0]
            windSlope = slopes[1]
        } else {
            reefSlope = reefTime / (reefVariance + ridge)
            windSlope = 0
        }

        guard reefSlope.isFinite, windSlope.isFinite, abs(reefSlope) > 0.03 else { return nil }
        return WindAwareReefingModel(
            averageReefCentimeters: averageReef,
            averageWindMPH: averageWind,
            averageFlightTimeSeconds: averageTime,
            reefSlopeSecondsPerCentimeter: reefSlope,
            windSlopeSecondsPerMPH: windSlope,
            sampleCount: samples.count
        )
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
