import Foundation
import PDFKit

struct OnlineMotorStatus {
    var designation: String
    var isReloadable: Bool
    var sourceURL: String

    var statusMessage: String {
        let label = isReloadable ? "RMS / reloadable" : "single-use"
        return "Official ARC motor list marks \(designation) as \(label)."
    }
}

enum ARCWebsiteService {
    static func syncCompetitionInfo() async throws -> ARCCompetitionInfo {
        let faqURL = URL(string: "https://www.rocketrychallenge.org/faq/")!
        let (data, response) = try await URLSession.shared.data(from: faqURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ARCWebsiteError.fetchFailed
        }

        let html = String(decoding: data, as: UTF8.self)
        let year = extractYear(from: html) ?? Calendar.current.component(.year, from: Date())
        let altitude = extractDouble(from: html, pattern: #"altitude of (\d+) feet"#) ?? 750
        let timeLow = extractDouble(from: html, pattern: #"between (\d+) and \d+ seconds"#) ?? 36
        let timeHigh = extractDouble(from: html, pattern: #"between \d+ and (\d+) seconds"#) ?? 39
        let maxMass = extractDouble(from: html, pattern: #"must not exceed (\d+) grams gross weight"#) ?? 650
        let minLength = extractDouble(from: html, pattern: #"no less than (\d+) millimeters"#) ?? 650
        let minDiameter = extractDouble(from: html, pattern: #"diameter of at least (\d+) millimeters"#) ?? 47
        let finalsDate = extractText(from: html, pattern: #"The official date is ([^.]+)\."#) ?? "Not found"
        let finalsLocation = extractText(from: html, pattern: #"at ([^.]+), about"#) ?? "Not found"
        let qualificationWindow = extractText(
            from: html,
            pattern: #"score between ([A-Za-z0-9, ]+ and [A-Za-z0-9, ]+)\."#
        ) ?? "See ARC website"

        return ARCCompetitionInfo(
            seasonYear: year,
            sourceName: "American Rocketry Challenge FAQ",
            sourceUpdated: "Synced live from rocketrychallenge.org for \(year)",
            altitudeGoalFeet: altitude,
            flightTimeRange: timeLow...timeHigh,
            maxLiftOffMassGrams: maxMass,
            minimumLengthMillimeters: minLength,
            minimumBodyDiameterMillimeters: minDiameter,
            qualificationWindow: qualificationWindow,
            finalsDate: finalsDate,
            finalsLocation: finalsLocation
        )
    }

    static func lookupNationals(profile: UserProfile, seasonYear: Int) async throws -> NationalsLookupResult {
        let url = URL(string: "https://www.rocketrychallenge.org/result/\(seasonYear)-finalists/")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ARCWebsiteError.fetchFailed
        }

        let html = String(decoding: data, as: UTF8.self)
        let normalizedSchool = normalize(profile.schoolOrganization)
        let normalizedTeamName = normalize(profile.teamName)
        let finalistsSection = extractText(from: html, pattern: #"## \(seasonYear) National Finalists(.*?)## \(seasonYear) National Finals Alternates"#) ?? html
        let alternatesSection = extractText(from: html, pattern: #"## \(seasonYear) National Finals Alternates(.*)"#) ?? ""

        if let match = firstMatchingLine(in: finalistsSection, queries: [normalizedTeamName, normalizedSchool]) {
            return NationalsLookupResult(
                status: .finalist,
                seasonYear: seasonYear,
                message: "This team appears on the ARC \(seasonYear) National Finalists list.",
                matchedName: match,
                sourceURL: url.absoluteString
            )
        }

        if let match = firstMatchingLine(in: alternatesSection, queries: [normalizedTeamName, normalizedSchool]) {
            return NationalsLookupResult(
                status: .alternate,
                seasonYear: seasonYear,
                message: "This team appears on the ARC \(seasonYear) National Finals alternates list.",
                matchedName: match,
                sourceURL: url.absoluteString
            )
        }

        return NationalsLookupResult(
            status: .notQualified,
            seasonYear: seasonYear,
            message: "No finalists or alternates match was found. ARC public results pages list school and team names, not numeric team IDs, so matching is based on the school/organization and optional team name fields.",
            matchedName: nil,
            sourceURL: url.absoluteString
        )
    }

    static func lookupMotorStatus(designation: String, seasonYear: Int) async throws -> OnlineMotorStatus {
        let pdfURL = try await approvedMotorPDFURL(for: seasonYear)
        let (data, response) = try await URLSession.shared.data(from: pdfURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ARCWebsiteError.fetchFailed
        }
        guard let document = PDFDocument(data: data) else {
            throw ARCWebsiteError.parseFailed
        }

        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")

        let escapedDesignation = NSRegularExpression.escapedPattern(for: designation)
        let pattern = #"(?m)\b\#(escapedDesignation)\b\s+(R\s+)?(?:Aerotech|Cesaroni|Estes|QJet\/AT|Quest)\b"#
        let isReloadable = matches(text: text, pattern: pattern)?.contains(" R ") == true || matches(text: text, pattern: pattern)?.contains("\nR ") == true

        if matches(text: text, pattern: pattern) != nil {
            return OnlineMotorStatus(
                designation: designation,
                isReloadable: isReloadable,
                sourceURL: pdfURL.absoluteString
            )
        }

        throw ARCWebsiteError.motorNotFound
    }

    private static func extractYear(from html: String) -> Int? {
        let text = extractText(from: html, pattern: #"### (\d{4}) Competition"#)
        return text.flatMap(Int.init)
    }

    private static func approvedMotorPDFURL(for seasonYear: Int) async throws -> URL {
        let defaultURL = URL(string: "https://www.rocketrychallenge.org/wp-content/uploads/Rocket-Motors-Approved-for-Use-in-ARC-2026-June-4-2025.pdf")!
        let rulesURL = URL(string: "https://www.rocketrychallenge.org/resource/\(seasonYear)-american-rocketry-challenge-rules/")!
        let (data, response) = try await URLSession.shared.data(from: rulesURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            return defaultURL
        }

        let html = String(decoding: data, as: UTF8.self)
        if let pdfString = extractText(from: html, pattern: #"(https://www\.rocketrychallenge\.org/[^"]*Rocket-Motors-Approved[^"]*\.pdf)"#),
           let url = URL(string: pdfString) {
            return url
        }
        if let relativePath = extractText(from: html, pattern: #"(/wp-content/uploads/[^"]*Rocket-Motors-Approved[^"]*\.pdf)"#),
           let url = URL(string: "https://www.rocketrychallenge.org\(relativePath)") {
            return url
        }
        return defaultURL
    }

    private static func extractDouble(from text: String, pattern: String) -> Double? {
        extractText(from: text, pattern: pattern).flatMap(Double.init)
    }

    private static func extractText(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return cleanWebsiteText(String(text[captureRange]))
    }

    private static func matches(text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range(at: 0), in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }

    private static func normalize(_ value: String) -> String {
        cleanWebsiteText(value)
            .lowercased()
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatchingLine(in text: String, queries: [String]) -> String? {
        let rowSeparatedText = text
            .replacingOccurrences(of: #"</(tr|li|p|h[1-6])>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        let normalizedText = rowSeparatedText
            .components(separatedBy: .newlines)
            .map { cleanWebsiteText($0) }
            .filter { !$0.isEmpty }

        for line in normalizedText {
            let normalizedLine = normalize(line)
            for query in queries where !query.isEmpty {
                if normalizedLine.contains(query) {
                    return line
                }
            }
        }
        return nil
    }

    private static func cleanWebsiteText(_ value: String) -> String {
        value.arcPlainText
    }
}

enum ARCWebsiteError: LocalizedError {
    case fetchFailed
    case parseFailed
    case motorNotFound

    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "Could not fetch ARC website data."
        case .parseFailed:
            return "Could not read the ARC motor PDF."
        case .motorNotFound:
            return "That motor was not found in the current ARC approved motor list."
        }
    }
}
