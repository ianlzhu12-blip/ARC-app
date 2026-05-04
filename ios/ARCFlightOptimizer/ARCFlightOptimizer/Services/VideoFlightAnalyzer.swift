import AVFoundation
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct PickedFlightVideo: Transferable {
    var attachment: FlightAttachment

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let attachment = try VideoFlightAnalyzer.copyVideoIntoAppStorage(from: received.file)
            return PickedFlightVideo(attachment: attachment)
        }
    }
}

struct VideoFlightAnalysisResult {
    var durationSeconds: Double
    var fileSizeMegabytes: Double
    var modelConfidence: Double
    var summary: String
}

struct FlightIssueAnalysis {
    var title: String
    var summary: String
    var evidence: [String]
    var recommendations: [String]
    var confidence: Double
    var severityColorName: String
}

enum VideoFlightAnalyzer {
    static func copyVideoIntoAppStorage(from sourceURL: URL) throws -> FlightAttachment {
        let folder = try attachmentFolder()
        let safeName = sanitizedFileName(sourceURL.lastPathComponent.isEmpty ? "LaunchVideo.mov" : sourceURL.lastPathComponent)
        let destination = folder.appendingPathComponent("\(UUID().uuidString)-\(safeName)")

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)

        return FlightAttachment(
            fileName: safeName,
            kind: .video,
            localPath: destination.lastPathComponent
        )
    }

    static func deleteStoredVideo(for attachment: FlightAttachment) {
        guard attachment.kind == .video,
              let localPath = attachment.localPath,
              let videoURL = try? attachmentFolder().appendingPathComponent(localPath),
              FileManager.default.fileExists(atPath: videoURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: videoURL)
    }

    static func analyze(_ attachment: FlightAttachment) async throws -> VideoFlightAnalysisResult {
        guard attachment.kind == .video,
              let localPath = attachment.localPath else {
            throw VideoFlightAnalyzerError.missingVideo
        }

        let videoURL = try attachmentFolder().appendingPathComponent(localPath)
        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw VideoFlightAnalyzerError.missingVideo
        }

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let resourceValues = try videoURL.resourceValues(forKeys: [.fileSizeKey])
        let fileSizeMB = Double(resourceValues.fileSize ?? 0) / 1_000_000
        let confidence = modelConfidence(durationSeconds: duration, fileSizeMegabytes: fileSizeMB)

        let summary = makeSummary(
            durationSeconds: duration,
            fileSizeMegabytes: fileSizeMB,
            modelConfidence: confidence
        )
        return VideoFlightAnalysisResult(
            durationSeconds: duration,
            fileSizeMegabytes: fileSizeMB,
            modelConfidence: confidence,
            summary: summary
        )
    }

    static func diagnoseFlight(
        flight: Flight,
        rocket: Rocket?,
        targetAltitudeFeet: Double,
        targetFlightTimeRange: ClosedRange<Double>?
    ) -> FlightIssueAnalysis {
        let videoSignals = flight.attachments.filter {
            $0.kind == .video && ($0.videoModelConfidence ?? 0) > 0
        }
        let bestVideoConfidence = videoSignals.map { $0.videoModelConfidence ?? 0 }.max() ?? 0
        let videoTime = videoSignals.compactMap(\.videoEstimatedFlightTimeSeconds).first
        let effectiveTime = flight.flightTimeSeconds ?? videoTime
        let altitudeError = flight.measuredAltitudeFeet - targetAltitudeFeet
        let absoluteAltitudeError = abs(altitudeError)
        var evidence: [String] = []
        var recommendations: [String] = []
        var causes: [String] = []

        if absoluteAltitudeError <= 15 {
            evidence.append("Altitude was within \(Int(absoluteAltitudeError.rounded())) ft of target.")
        } else if altitudeError < 0 {
            evidence.append("Flight was \(Int(absoluteAltitudeError.rounded())) ft low.")
            if flight.rocketMassGrams > (rocket?.dryMassGrams ?? flight.rocketMassGrams) + 120 {
                causes.append("loaded mass may be high")
                recommendations.append("Try a small mass reduction or compare against lighter flights with the same motor.")
            }
            if flight.weather.windMPH >= 10 {
                causes.append("wind may have caused weathercocking or extra drag")
                recommendations.append("In similar wind, consider launching in calmer air or checking rod angle and rail friction.")
            }
            if flight.weather.temperatureF < 45 {
                causes.append("cold air and motor performance may have reduced altitude")
                recommendations.append("Compare against warmer flights before making a large weight change.")
            }
            if causes.isEmpty {
                causes.append("mass, drag, or launch friction may have reduced apogee")
                recommendations.append("Review rail fit, fin alignment, and compare weight against nearby flights.")
            }
        } else {
            evidence.append("Flight was \(Int(absoluteAltitudeError.rounded())) ft high.")
            causes.append("rocket may be too light for this motor/weather setup")
            recommendations.append("Add small ballast increments and re-check the predicted apogee.")
            if flight.weather.windMPH <= 3 {
                evidence.append("Low wind likely helped preserve altitude.")
            }
        }

        if let targetFlightTimeRange, let effectiveTime {
            if targetFlightTimeRange.contains(effectiveTime) {
                evidence.append("Flight time was inside the target window at \(String(format: "%.1f", effectiveTime)) s.")
            } else if effectiveTime < targetFlightTimeRange.lowerBound {
                evidence.append("Flight time was \(String(format: "%.1f", targetFlightTimeRange.lowerBound - effectiveTime)) s short.")
                causes.append("descent may be too fast")
                recommendations.append("Increase parachute area or inspect deployment timing if the video shows a late canopy.")
            } else {
                evidence.append("Flight time was \(String(format: "%.1f", effectiveTime - targetFlightTimeRange.upperBound)) s long.")
                causes.append("descent may be too slow")
                recommendations.append("Reduce parachute size slightly or check for excessive drift in wind.")
            }
        } else if let videoTime {
            evidence.append("Video estimated flight duration at \(String(format: "%.1f", videoTime)) s.")
        } else if flight.attachments.contains(where: { $0.kind == .video }) {
            evidence.append("Video is attached but has not been analyzed yet.")
            recommendations.append("Tap Analyze on the video while editing this flight to improve the diagnosis.")
        } else {
            recommendations.append("Attach and analyze a launch video to help explain boost, coast, deployment, and descent problems.")
        }

        if flight.weather.windMPH >= 12 {
            evidence.append("Wind was high at \(Int(flight.weather.windMPH.rounded())) mph.")
            if !causes.contains("wind may have caused weathercocking or extra drag") {
                causes.append("wind may have affected trajectory and drift")
            }
        }
        if flight.weather.humidityPercent >= 80 {
            evidence.append("Humidity was high at \(Int(flight.weather.humidityPercent.rounded()))%.")
        }
        if flight.eggStatus == .cracked || flight.eggStatus == .broken {
            causes.append("landing or deployment shock damaged the payload")
            recommendations.append("Review descent rate, shock cord length, and padding before changing altitude weight.")
        }

        if let rocket {
            let loadedDelta = flight.rocketMassGrams - rocket.dryMassGrams
            evidence.append("Loaded mass was \(Int(flight.rocketMassGrams.rounded())) g, about \(Int(loadedDelta.rounded())) g above dry mass.")
            evidence.append("Parachute was \(Int(flight.parachuteSizeInches.rounded())) in on a \(rocket.material.displayName.lowercased()) rocket.")
        }
        if let reefedCentimeters = flight.parachuteReefedCentimeters {
            evidence.append("Parachute reefing was logged at \(String(format: "%.1f", reefedCentimeters)) cm.")
        }

        if bestVideoConfidence > 0 {
            evidence.append("Video signal confidence: \(Int((bestVideoConfidence * 100).rounded()))%.")
        }

        let confidence = min(
            0.95,
            0.35
            + (bestVideoConfidence * 0.28)
            + (effectiveTime == nil ? 0 : 0.16)
            + (flight.weather.windMPH != 0 || flight.weather.temperatureF != 0 ? 0.12 : 0)
            + (rocket == nil ? 0 : 0.12)
        )
        let issueText = causes.isEmpty ? "flight looked mostly healthy" : causes.prefix(2).joined(separator: " and ")
        let title: String
        let severity: String
        if absoluteAltitudeError <= 15,
           let targetFlightTimeRange,
           let effectiveTime,
           targetFlightTimeRange.contains(effectiveTime),
           flight.eggStatus != .cracked,
           flight.eggStatus != .broken {
            title = "Good flight"
            severity = "mint"
        } else if absoluteAltitudeError > 75 || flight.eggStatus == .broken {
            title = "Likely issue: \(issueText)"
            severity = "orange"
        } else {
            title = causes.isEmpty ? "Minor tuning notes" : "Possible issue: \(issueText)"
            severity = "amber"
        }

        let summary = "AI diagnosis: \(title.lowercased()). Confidence \(Int((confidence * 100).rounded()))%."
        return FlightIssueAnalysis(
            title: title,
            summary: summary,
            evidence: Array(evidence.prefix(5)),
            recommendations: Array(recommendations.prefix(3)),
            confidence: confidence,
            severityColorName: severity
        )
    }

    static func attachmentFolder() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = documents.appendingPathComponent("FlightVideos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    private static func sanitizedFileName(_ fileName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ "))
        let cleanedScalars = fileName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let cleaned = String(cleanedScalars).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "LaunchVideo.mov" : cleaned
    }

    private static func modelConfidence(durationSeconds: Double, fileSizeMegabytes: Double) -> Double {
        guard durationSeconds.isFinite else { return 0.25 }
        var confidence = 0.45
        if (12...80).contains(durationSeconds) {
            confidence += 0.3
        } else if (8...120).contains(durationSeconds) {
            confidence += 0.18
        }
        if fileSizeMegabytes > 4 {
            confidence += 0.08
        }
        return min(max(confidence, 0.2), 0.85)
    }

    private static func makeSummary(durationSeconds: Double, fileSizeMegabytes: Double, modelConfidence: Double) -> String {
        let durationText = durationSeconds.isFinite ? String(format: "%.1f", durationSeconds) : "unknown"
        let fileSizeText = String(format: "%.1f", fileSizeMegabytes)
        let confidenceText = "\(Int((modelConfidence * 100).rounded()))%"
        var notes = [
            "Video analyzed: \(durationText) s clip, \(fileSizeText) MB.",
            "AI confidence \(confidenceText). This video now helps the weight model by strengthening this flight's timing/calibration signal."
        ]

        if durationSeconds.isFinite {
            if durationSeconds < 10 {
                notes.append("Clip is short, so it may miss descent or touchdown.")
            } else if durationSeconds > 80 {
                notes.append("Clip is long; trimming around launch can make future AI analysis faster.")
            } else {
                notes.append("Clip length looks good for launch-to-landing review, so flight time can be used if the log does not already have one.")
            }
        }

        return notes.joined(separator: " ")
    }
}

enum VideoFlightAnalyzerError: LocalizedError {
    case missingVideo

    var errorDescription: String? {
        switch self {
        case .missingVideo:
            return "The saved video file could not be found. Try attaching it again from Photos."
        }
    }
}
