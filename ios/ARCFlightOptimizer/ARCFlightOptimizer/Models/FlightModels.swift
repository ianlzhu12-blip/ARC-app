import Foundation

extension String {
    var arcPlainText: String {
        self
            .replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"<br\s*/?>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"</?(p|div|span|h[1-6]|tr|td|th|li|ul|ol|table|tbody|thead|strong|em|a)[^>]*>"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8217;", with: "'")
            .replacingOccurrences(of: "&#8211;", with: "-")
            .replacingOccurrences(of: "&#8212;", with: "-")
            .replacingOccurrences(of: "&#038;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FlightMode: String, CaseIterable, Codable, Identifiable {
    case hobby = "Hobby Flying"
    case competition = "Competition"
    case nationals = "Nationals"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .hobby: return "Hobby"
        case .competition: return "Competition"
        case .nationals: return "Nationals"
        }
    }

    var detail: String {
        switch self {
        case .hobby:
            return "Flexible logging for fun flights, experiments, and local practice."
        case .competition:
            return "Target-focused practice mode with scoring and consistency tracking."
        case .nationals:
            return "Competition-day mode with launch window timing and locked configurations."
        }
    }
}

enum MotorType: String, CaseIterable, Codable, Identifiable {
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case e = "E"
    case f = "F"
    case g = "G"
    case h = "H"
    case other = "Other"

    var id: String { rawValue }

    var impulseScore: Double {
        switch self {
        case .a: return 1
        case .b: return 2
        case .c: return 3
        case .d: return 4
        case .e: return 5
        case .f: return 6
        case .g: return 7
        case .h: return 8
        case .other: return 5
        }
    }
}

enum RocketMaterial: String, CaseIterable, Codable, Identifiable {
    case cardboard = "Cardboard"
    case fiberglass = "Fiberglass"
    case carbonFiber = "Carbon Fiber"
    case plastic = "Plastic"
    case woodComposite = "Wood Composite"
    case mixed = "Mixed"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var dragFactor: Double {
        switch self {
        case .cardboard: return 1.0
        case .fiberglass: return 0.96
        case .carbonFiber: return 0.94
        case .plastic: return 1.03
        case .woodComposite: return 1.02
        case .mixed: return 1.0
        }
    }
}

enum EggStatus: String, CaseIterable, Codable, Identifiable {
    case unknown = "Unknown"
    case intact = "Intact"
    case cracked = "Cracked"
    case broken = "Broken"
    case notCarried = "Not Carried"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unknown: return "Not recorded"
        case .intact: return "Intact"
        case .cracked: return "Cracked"
        case .broken: return "Broken"
        case .notCarried: return "No egg carried"
        }
    }
}

struct MotorSpec: Identifiable, Codable, Hashable {
    var id: String { designation }
    var designation: String
    var manufacturer: String
    var casing: String
    var propellantMassGrams: Double
    var totalImpulseNS: Double
    var reloadable: Bool

    var motorClass: MotorType {
        let first = designation.first?.uppercased() ?? "O"
        return MotorType(rawValue: first) ?? .other
    }
}

struct ARCCompetitionInfo: Codable, Hashable {
    var seasonYear: Int
    var sourceName: String
    var sourceUpdated: String
    var lastCheckedAt: Date
    var altitudeGoalFeet: Double
    var flightTimeRange: ClosedRange<Double>
    var maxLiftOffMassGrams: Double
    var minimumLengthMillimeters: Double
    var minimumBodyDiameterMillimeters: Double
    var qualificationWindow: String
    var finalsDate: String
    var finalsLocation: String

    init(
        seasonYear: Int,
        sourceName: String,
        sourceUpdated: String,
        lastCheckedAt: Date = Date(),
        altitudeGoalFeet: Double,
        flightTimeRange: ClosedRange<Double>,
        maxLiftOffMassGrams: Double,
        minimumLengthMillimeters: Double,
        minimumBodyDiameterMillimeters: Double,
        qualificationWindow: String,
        finalsDate: String,
        finalsLocation: String
    ) {
        self.seasonYear = seasonYear
        self.sourceName = sourceName.arcPlainText
        self.sourceUpdated = sourceUpdated.arcPlainText
        self.lastCheckedAt = lastCheckedAt
        self.altitudeGoalFeet = altitudeGoalFeet
        self.flightTimeRange = flightTimeRange
        self.maxLiftOffMassGrams = maxLiftOffMassGrams
        self.minimumLengthMillimeters = minimumLengthMillimeters
        self.minimumBodyDiameterMillimeters = minimumBodyDiameterMillimeters
        self.qualificationWindow = qualificationWindow.arcPlainText
        self.finalsDate = finalsDate.arcPlainText
        self.finalsLocation = finalsLocation.arcPlainText
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seasonYear = try container.decodeIfPresent(Int.self, forKey: .seasonYear) ?? 2026
        sourceName = try container.decode(String.self, forKey: .sourceName).arcPlainText
        sourceUpdated = try container.decode(String.self, forKey: .sourceUpdated).arcPlainText
        lastCheckedAt = try container.decodeIfPresent(Date.self, forKey: .lastCheckedAt) ?? Date()
        altitudeGoalFeet = try container.decode(Double.self, forKey: .altitudeGoalFeet)
        flightTimeRange = try container.decode(ClosedRange<Double>.self, forKey: .flightTimeRange)
        maxLiftOffMassGrams = try container.decode(Double.self, forKey: .maxLiftOffMassGrams)
        minimumLengthMillimeters = try container.decode(Double.self, forKey: .minimumLengthMillimeters)
        minimumBodyDiameterMillimeters = try container.decode(Double.self, forKey: .minimumBodyDiameterMillimeters)
        qualificationWindow = try container.decode(String.self, forKey: .qualificationWindow).arcPlainText
        finalsDate = try container.decode(String.self, forKey: .finalsDate).arcPlainText
        finalsLocation = try container.decode(String.self, forKey: .finalsLocation).arcPlainText
    }
}

struct PersonalAccount: Codable, Hashable {
    var displayName: String = ""
    var email: String = ""
    var registeredAt: Date = Date()

    var isRegistered: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct TeamMember: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var email: String
    var role: String = "Member"
    var joinedAt: Date = Date()
}

struct Team: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var school: String
    var joinCode: String
    var members: [TeamMember]

    init(
        id: UUID = UUID(),
        name: String,
        school: String,
        joinCode: String = Team.makeJoinCode(),
        members: [TeamMember] = []
    ) {
        self.id = id
        self.name = name
        self.school = school
        self.joinCode = joinCode
        self.members = members
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        school = try container.decode(String.self, forKey: .school)
        joinCode = try container.decodeIfPresent(String.self, forKey: .joinCode) ?? Team.makeJoinCode()
        members = try container.decodeIfPresent([TeamMember].self, forKey: .members) ?? []
    }

    static func makeJoinCode() -> String {
        String(UUID().uuidString.prefix(6)).uppercased()
    }
}

struct Rocket: Identifiable, Codable, Hashable {
    var id = UUID()
    var teamID: UUID
    var name: String
    var dryMassGrams: Double
    var diameterMillimeters: Double
    var material: RocketMaterial = .cardboard
    var parachuteSizeInches: Double = 18
    var defaultMotorDesignation: String = "F24W-4,7"
    var heightMillimeters: Double = 700
    var widthMillimeters: Double = 66
    var lockedForNationals: Bool = false
    var importedFromOpenRocket: Bool = false
    var openRocketFileName: String?
    var openRocketDesignSummary: String?

    init(
        id: UUID = UUID(),
        teamID: UUID,
        name: String,
        dryMassGrams: Double,
        diameterMillimeters: Double,
        material: RocketMaterial = .cardboard,
        parachuteSizeInches: Double = 18,
        defaultMotorDesignation: String = "F24W-4,7",
        heightMillimeters: Double = 700,
        widthMillimeters: Double = 66,
        lockedForNationals: Bool = false,
        importedFromOpenRocket: Bool = false,
        openRocketFileName: String? = nil,
        openRocketDesignSummary: String? = nil
    ) {
        self.id = id
        self.teamID = teamID
        self.name = name
        self.dryMassGrams = dryMassGrams
        self.diameterMillimeters = diameterMillimeters
        self.material = material
        self.parachuteSizeInches = parachuteSizeInches
        self.defaultMotorDesignation = defaultMotorDesignation
        self.heightMillimeters = heightMillimeters
        self.widthMillimeters = widthMillimeters
        self.lockedForNationals = lockedForNationals
        self.importedFromOpenRocket = importedFromOpenRocket
        self.openRocketFileName = openRocketFileName
        self.openRocketDesignSummary = openRocketDesignSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        teamID = try container.decode(UUID.self, forKey: .teamID)
        name = try container.decode(String.self, forKey: .name)
        dryMassGrams = try container.decode(Double.self, forKey: .dryMassGrams)
        diameterMillimeters = try container.decode(Double.self, forKey: .diameterMillimeters)
        material = try container.decodeIfPresent(RocketMaterial.self, forKey: .material) ?? .cardboard
        parachuteSizeInches = try container.decodeIfPresent(Double.self, forKey: .parachuteSizeInches) ?? 18
        defaultMotorDesignation = try container.decodeIfPresent(String.self, forKey: .defaultMotorDesignation) ?? "F24W-4,7"
        heightMillimeters = try container.decodeIfPresent(Double.self, forKey: .heightMillimeters) ?? 700
        widthMillimeters = try container.decodeIfPresent(Double.self, forKey: .widthMillimeters) ?? diameterMillimeters
        lockedForNationals = try container.decodeIfPresent(Bool.self, forKey: .lockedForNationals) ?? false
        importedFromOpenRocket = try container.decodeIfPresent(Bool.self, forKey: .importedFromOpenRocket) ?? false
        openRocketFileName = try container.decodeIfPresent(String.self, forKey: .openRocketFileName)
        openRocketDesignSummary = try container.decodeIfPresent(String.self, forKey: .openRocketDesignSummary)
    }
}

struct Weather: Codable, Hashable {
    var temperatureF: Double
    var windMPH: Double
    var humidityPercent: Double
    var location: String
}

struct LaunchChecklistItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var isComplete: Bool = false

    init(id: UUID = UUID(), title: String, isComplete: Bool = false) {
        self.id = id
        self.title = title
        self.isComplete = isComplete
    }
}

enum FlightAttachmentKind: String, Codable, Hashable {
    case file
    case video
}

struct FlightAttachment: Identifiable, Codable, Hashable {
    var id = UUID()
    var fileName: String
    var kind: FlightAttachmentKind = .file
    var localPath: String?
    var analysisSummary: String?
    var videoEstimatedFlightTimeSeconds: Double?
    var videoModelConfidence: Double?
    var addedAt: Date = Date()

    init(
        id: UUID = UUID(),
        fileName: String,
        kind: FlightAttachmentKind = .file,
        localPath: String? = nil,
        analysisSummary: String? = nil,
        videoEstimatedFlightTimeSeconds: Double? = nil,
        videoModelConfidence: Double? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.kind = kind
        self.localPath = localPath
        self.analysisSummary = analysisSummary
        self.videoEstimatedFlightTimeSeconds = videoEstimatedFlightTimeSeconds
        self.videoModelConfidence = videoModelConfidence
        self.addedAt = addedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decode(String.self, forKey: .fileName)
        kind = try container.decodeIfPresent(FlightAttachmentKind.self, forKey: .kind) ?? .file
        localPath = try container.decodeIfPresent(String.self, forKey: .localPath)
        analysisSummary = try container.decodeIfPresent(String.self, forKey: .analysisSummary)
        videoEstimatedFlightTimeSeconds = try container.decodeIfPresent(Double.self, forKey: .videoEstimatedFlightTimeSeconds)
        videoModelConfidence = try container.decodeIfPresent(Double.self, forKey: .videoModelConfidence)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
    }
}

struct Flight: Identifiable, Codable, Hashable {
    var id = UUID()
    var rocketID: UUID
    var teamID: UUID
    var flownAt: Date
    var motorType: MotorType
    var motorDesignation: String
    var rocketMassGrams: Double
    var weather: Weather
    var measuredAltitudeFeet: Double
    var targetAltitudeFeet: Double?
    var flightTimeSeconds: Double?
    var parachuteSizeInches: Double
    var parachuteReefedCentimeters: Double?
    var descentSystem: String
    var eggStatus: EggStatus
    var notes: String
    var attachments: [FlightAttachment]
    var excludedFromAI: Bool
    var round: String?

    init(
        id: UUID = UUID(),
        rocketID: UUID,
        teamID: UUID,
        flownAt: Date,
        motorType: MotorType,
        motorDesignation: String,
        rocketMassGrams: Double,
        weather: Weather,
        measuredAltitudeFeet: Double,
        targetAltitudeFeet: Double? = nil,
        flightTimeSeconds: Double? = nil,
        parachuteSizeInches: Double,
        parachuteReefedCentimeters: Double? = nil,
        descentSystem: String,
        eggStatus: EggStatus = .unknown,
        notes: String,
        attachments: [FlightAttachment] = [],
        excludedFromAI: Bool = false,
        round: String? = nil
    ) {
        self.id = id
        self.rocketID = rocketID
        self.teamID = teamID
        self.flownAt = flownAt
        self.motorType = motorType
        self.motorDesignation = motorDesignation
        self.rocketMassGrams = rocketMassGrams
        self.weather = weather
        self.measuredAltitudeFeet = measuredAltitudeFeet
        self.targetAltitudeFeet = targetAltitudeFeet
        self.flightTimeSeconds = flightTimeSeconds
        self.parachuteSizeInches = parachuteSizeInches
        self.parachuteReefedCentimeters = parachuteReefedCentimeters
        self.descentSystem = descentSystem
        self.eggStatus = eggStatus
        self.notes = notes
        self.attachments = attachments
        self.excludedFromAI = excludedFromAI
        self.round = round
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rocketID = try container.decode(UUID.self, forKey: .rocketID)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        flownAt = try container.decode(Date.self, forKey: .flownAt)
        motorType = try container.decode(MotorType.self, forKey: .motorType)
        motorDesignation = try container.decode(String.self, forKey: .motorDesignation)
        rocketMassGrams = try container.decode(Double.self, forKey: .rocketMassGrams)
        weather = try container.decode(Weather.self, forKey: .weather)
        measuredAltitudeFeet = try container.decode(Double.self, forKey: .measuredAltitudeFeet)
        targetAltitudeFeet = try container.decodeIfPresent(Double.self, forKey: .targetAltitudeFeet)
        flightTimeSeconds = try container.decodeIfPresent(Double.self, forKey: .flightTimeSeconds)
        parachuteSizeInches = try container.decode(Double.self, forKey: .parachuteSizeInches)
        parachuteReefedCentimeters = try container.decodeIfPresent(Double.self, forKey: .parachuteReefedCentimeters)
        descentSystem = try container.decode(String.self, forKey: .descentSystem)
        eggStatus = try container.decodeIfPresent(EggStatus.self, forKey: .eggStatus) ?? .unknown
        notes = try container.decode(String.self, forKey: .notes)
        attachments = try container.decodeIfPresent([FlightAttachment].self, forKey: .attachments) ?? []
        excludedFromAI = try container.decodeIfPresent(Bool.self, forKey: .excludedFromAI) ?? false
        round = try container.decodeIfPresent(String.self, forKey: .round)
    }
}

struct CloudSyncSettings: Codable, Hashable {
    var enabled: Bool = false
    var providerName: String = "iCloud"
    var workspaceID: String = ""
    var lastSyncAt: Date?

    var statusText: String {
        guard enabled else { return "iCloud sync is off." }
        if let lastSyncAt {
            return "iCloud sync is on. Last saved \(lastSyncAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return "iCloud sync is on. Save this logbook to iCloud to make it available to your Apple ID."
    }
}

struct FlightScoreSummary {
    var isDisqualified: Bool
    var disqualificationReasons: [String]
    var altitudePoints: Int
    var timePoints: Int

    var totalPoints: Int? {
        isDisqualified ? nil : altitudePoints + timePoints
    }
}

struct PredictionInput {
    var motorType: MotorType
    var motorDesignation: String
    var rocketMassGrams: Double
    var temperatureF: Double
    var windMPH: Double
    var humidityPercent: Double
    var rocketMaterial: RocketMaterial
    var parachuteSizeInches: Double
    var rocketHeightMillimeters: Double
    var rocketWidthMillimeters: Double
}

struct Prediction {
    var altitudeFeet: Double
    var confidence: Double
    var method: String

    var displayMethod: String {
        switch method {
        case "baseline":
            return "starter model"
        case "regression":
            return "flight-history model"
        default:
            return "prediction model"
        }
    }
}

struct Recommendation: Identifiable {
    var id = UUID()
    var title: String
    var detail: String
    var priority: Priority

    enum Priority: String {
        case high
        case medium
        case low
    }
}

struct OptimizationResult {
    var suggestedMassGrams: Double
    var suggestedAltitudeFeet: Double
    var massDeltaGrams: Double
    var confidence: Double
    var notes: [String]
    var reusableDelayDrillSeconds: Double?
    var suggestedReefedCentimeters: Double?
}

struct HeightTuningPoint: Identifiable {
    var id: String { "\(Int(targetAltitudeFeet))-\(Int(suggestedMassGrams))" }
    var targetAltitudeFeet: Double
    var suggestedMassGrams: Double
    var predictedAltitudeFeet: Double
    var confidence: Double
    var reusableDelayDrillSeconds: Double?
}

struct UserProfile: Codable, Hashable {
    var schoolOrganization: String = ""
    var teamNumber: String = ""
    var teamName: String = ""
}

enum NationalsQualificationStatus: String, Codable {
    case unknown
    case synced
    case finalist
    case alternate
    case notQualified
    case lookupFailed

    var displayTitle: String {
        switch self {
        case .unknown:
            return "Not checked yet"
        case .synced:
            return "Checked"
        case .finalist:
            return "Nationals finalist"
        case .alternate:
            return "Nationals alternate"
        case .notQualified:
            return "Not listed for Nationals"
        case .lookupFailed:
            return "Could not check Nationals"
        }
    }
}

struct NationalsLookupResult: Codable, Hashable {
    var status: NationalsQualificationStatus
    var seasonYear: Int
    var message: String
    var matchedName: String?
    var sourceURL: String

    var displayMessage: String {
        message.arcPlainText
    }

    var displayMatchedName: String? {
        matchedName?.arcPlainText
    }
}
