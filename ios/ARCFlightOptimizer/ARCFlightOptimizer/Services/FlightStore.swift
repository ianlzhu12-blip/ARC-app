import Foundation

@MainActor
final class FlightStore: ObservableObject {
    @Published var teams: [Team] = []
    @Published var rockets: [Rocket] = []
    @Published var flights: [Flight] = []
    @Published var flightMode: FlightMode = .hobby
    @Published var targetAltitudeFeet: Double = 800
    @Published var launchWindowSeconds = 45 * 60
    @Published var launchWindowEndsAt: Date?
    @Published var launchTimerState: LaunchTimerState = .stopped
    @Published var launchChecklistItems: [LaunchChecklistItem] = FlightStore.defaultLaunchChecklistItems
    @Published var profile = UserProfile()
    @Published var personalAccount = PersonalAccount()
    @Published var syncedCompetitionInfo = MotorCatalog.arc2026CompetitionInfo
    @Published var nationalsLookup: NationalsLookupResult?
    @Published var cloudSyncSettings = CloudSyncSettings()

    private let storageKey = "arc-flight-optimizer-ios-state-v1"
    private let iCloudStorageKey = "arc-flight-optimizer-icloud-state-v1"
    private var didAttemptAutomaticSync = false
    private var pendingSaveTask: Task<Void, Never>?
    static let defaultLaunchChecklistItems = [
        LaunchChecklistItem(title: "Confirm launch site weather"),
        LaunchChecklistItem(title: "Verify motor and delay"),
        LaunchChecklistItem(title: "Check recovery system"),
        LaunchChecklistItem(title: "Power on altimeter"),
        LaunchChecklistItem(title: "Record loaded mass")
    ]

    init() {
        load()
    }

    var activeRocket: Rocket? {
        rockets.first
    }

    var needsInitialSetup: Bool {
        rockets.isEmpty
    }

    var isCompetitionMode: Bool {
        flightMode == .competition || flightMode == .nationals
    }

    var isNationalsMode: Bool {
        flightMode == .nationals
    }

    var hasNationalsAccess: Bool {
        guard let status = nationalsLookup?.status else { return false }
        return status == .finalist || status == .alternate
    }

    var selectableFlightModes: [FlightMode] {
        hasNationalsAccess
            ? FlightMode.allCases
            : FlightMode.allCases.filter { $0 != .nationals }
    }

    func setFlightMode(_ mode: FlightMode) {
        flightMode = mode == .nationals && !hasNationalsAccess ? .competition : mode
        if mode == .competition || mode == .nationals {
            targetAltitudeFeet = syncedCompetitionInfo.altitudeGoalFeet
        }
        if flightMode != .nationals {
            stopLaunchWindow()
        }
        save()
    }

    func addTeam(name: String, school: String) {
        let member = personalAccount.isRegistered
            ? [TeamMember(name: personalAccount.displayName, email: personalAccount.email, role: "Owner")]
            : []
        teams.append(Team(name: name.isEmpty ? "New Team" : name, school: school, members: member))
        save()
    }

    func completeInitialSetup(
        mode: FlightMode,
        teamName: String,
        school: String,
        rocketName: String,
        dryMass: Double,
        diameter: Double,
        material: RocketMaterial,
        parachuteSize: Double,
        defaultMotorDesignation: String,
        heightMillimeters: Double,
        widthMillimeters: Double
    ) {
        teams = []
        rockets = []
        flights = []

        let members = personalAccount.isRegistered
            ? [TeamMember(name: personalAccount.displayName, email: personalAccount.email, role: "Owner")]
            : []
        let team = Team(
            name: teamName.isEmpty ? "My Team" : teamName,
            school: school.isEmpty ? "Independent" : school,
            members: members
        )
        teams = [team]
        flightMode = mode == .nationals && !hasNationalsAccess ? .competition : mode
        targetAltitudeFeet = (flightMode == .competition || flightMode == .nationals) ? syncedCompetitionInfo.altitudeGoalFeet : 800
        stopLaunchWindow()

        rockets = [
            Rocket(
                teamID: team.id,
                name: rocketName.isEmpty ? "My Rocket" : rocketName,
                dryMassGrams: dryMass,
                diameterMillimeters: diameter,
                material: material,
                parachuteSizeInches: parachuteSize,
                defaultMotorDesignation: defaultMotorDesignation,
                heightMillimeters: heightMillimeters,
                widthMillimeters: widthMillimeters,
                lockedForNationals: flightMode == .nationals
            )
        ]
        save()
    }

    func addRocket(name: String, teamID: UUID, dryMass: Double, diameter: Double) {
        rockets.append(
            Rocket(
                teamID: teamID,
                name: name.isEmpty ? "New Rocket" : name,
                dryMassGrams: dryMass,
                diameterMillimeters: diameter,
                material: .cardboard,
                parachuteSizeInches: 18,
                defaultMotorDesignation: MotorCatalog.motors(for: flightMode).first?.designation ?? "F24W-4,7",
                heightMillimeters: 700,
                widthMillimeters: diameter,
                lockedForNationals: isNationalsMode
            )
        )
        save()
    }

    func addRocket(
        name: String,
        teamID: UUID,
        dryMass: Double,
        diameter: Double,
        material: RocketMaterial,
        parachuteSize: Double,
        defaultMotorDesignation: String,
        heightMillimeters: Double,
        widthMillimeters: Double,
        importedFromOpenRocket: Bool = false,
        openRocketFileName: String? = nil,
        openRocketDesignSummary: String? = nil
    ) {
        rockets.append(
            Rocket(
                teamID: teamID,
                name: name.isEmpty ? "New Rocket" : name,
                dryMassGrams: dryMass,
                diameterMillimeters: diameter,
                material: material,
                parachuteSizeInches: parachuteSize,
                defaultMotorDesignation: defaultMotorDesignation,
                heightMillimeters: heightMillimeters,
                widthMillimeters: widthMillimeters,
                lockedForNationals: isNationalsMode,
                importedFromOpenRocket: importedFromOpenRocket,
                openRocketFileName: openRocketFileName,
                openRocketDesignSummary: openRocketDesignSummary
            )
        )
        save()
    }

    func updateRocket(
        id: UUID,
        name: String,
        teamID: UUID,
        dryMass: Double,
        diameter: Double,
        material: RocketMaterial,
        parachuteSize: Double,
        defaultMotorDesignation: String,
        heightMillimeters: Double,
        widthMillimeters: Double,
        importedFromOpenRocket: Bool? = nil,
        openRocketFileName: String? = nil,
        openRocketDesignSummary: String? = nil
    ) {
        guard let index = rockets.firstIndex(where: { $0.id == id }) else { return }
        rockets[index].teamID = teamID
        rockets[index].name = name.isEmpty ? "New Rocket" : name
        rockets[index].dryMassGrams = dryMass
        rockets[index].diameterMillimeters = diameter
        rockets[index].material = material
        rockets[index].parachuteSizeInches = parachuteSize
        rockets[index].defaultMotorDesignation = defaultMotorDesignation
        rockets[index].heightMillimeters = heightMillimeters
        rockets[index].widthMillimeters = widthMillimeters
        if let importedFromOpenRocket {
            rockets[index].importedFromOpenRocket = importedFromOpenRocket
        }
        if let openRocketFileName {
            rockets[index].openRocketFileName = openRocketFileName
        }
        if let openRocketDesignSummary {
            rockets[index].openRocketDesignSummary = openRocketDesignSummary
        }
        save()
    }

    func deleteRocket(id: UUID) {
        rockets.removeAll { $0.id == id }
        flights.removeAll { $0.rocketID == id }
        save()
    }

    func addFlight(
        rocket: Rocket,
        motorDesignation: String,
        mass: Double,
        weather: Weather,
        altitude: Double,
        targetAltitude: Double? = nil,
        flightTimeSeconds: Double?,
        parachute: Double,
        reefedCentimeters: Double? = nil,
        descentSystem: String,
        eggStatus: EggStatus,
        notes: String,
        attachments: [FlightAttachment] = []
    ) {
        flights.insert(
            Flight(
                rocketID: rocket.id,
                teamID: rocket.teamID,
                flownAt: Date(),
                motorType: MotorCatalog.motor(named: motorDesignation)?.motorClass ?? .other,
                motorDesignation: motorDesignation,
                rocketMassGrams: mass,
                weather: weather,
                measuredAltitudeFeet: altitude,
                targetAltitudeFeet: targetAltitude,
                flightTimeSeconds: flightTimeSeconds,
                parachuteSizeInches: parachute,
                parachuteReefedCentimeters: reefedCentimeters,
                descentSystem: descentSystem,
                eggStatus: eggStatus,
                notes: notes,
                attachments: attachments,
                round: flightMode.shortTitle
            ),
            at: 0
        )
        save()
    }

    func updateFlight(
        id: UUID,
        rocket: Rocket,
        motorDesignation: String,
        mass: Double,
        weather: Weather,
        altitude: Double,
        targetAltitude: Double? = nil,
        flightTimeSeconds: Double?,
        parachute: Double,
        reefedCentimeters: Double? = nil,
        descentSystem: String,
        eggStatus: EggStatus,
        notes: String,
        attachments: [FlightAttachment]? = nil
    ) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        flights[index].rocketID = rocket.id
        flights[index].teamID = rocket.teamID
        flights[index].motorType = MotorCatalog.motor(named: motorDesignation)?.motorClass ?? .other
        flights[index].motorDesignation = motorDesignation
        flights[index].rocketMassGrams = mass
        flights[index].weather = weather
        flights[index].measuredAltitudeFeet = altitude
        flights[index].targetAltitudeFeet = targetAltitude
        flights[index].flightTimeSeconds = flightTimeSeconds
        flights[index].parachuteSizeInches = parachute
        flights[index].parachuteReefedCentimeters = reefedCentimeters
        flights[index].descentSystem = descentSystem
        flights[index].eggStatus = eggStatus
        flights[index].notes = notes
        if let attachments {
            flights[index].attachments = attachments
        }
        flights[index].round = flightMode.shortTitle
        save()
    }

    func importFlights(_ importedFlights: [Flight]) {
        let existingIDs = Set(flights.map(\.id))
        let newFlights = importedFlights.filter { !existingIDs.contains($0.id) }
        flights.insert(contentsOf: newFlights, at: 0)
        save()
    }

    func deleteFlight(id: UUID) {
        flights.removeAll { $0.id == id }
        save()
    }

    func rocket(for flight: Flight) -> Rocket? {
        rockets.first { $0.id == flight.rocketID }
    }

    func scoreSummary(for flight: Flight) -> FlightScoreSummary {
        guard (flight.round ?? "") != FlightMode.hobby.shortTitle else {
            return FlightScoreSummary(isDisqualified: false, disqualificationReasons: [], altitudePoints: 0, timePoints: 0)
        }

        var reasons: [String] = []
        guard let rocket = rocket(for: flight) else {
            return FlightScoreSummary(
                isDisqualified: true,
                disqualificationReasons: ["Rocket configuration could not be found."],
                altitudePoints: 0,
                timePoints: 0
            )
        }

        let info = syncedCompetitionInfo
        if rocket.heightMillimeters < info.minimumLengthMillimeters {
            reasons.append("rocket length below \(Int(info.minimumLengthMillimeters)) mm")
        }
        if rocket.widthMillimeters < info.minimumBodyDiameterMillimeters {
            reasons.append("rocket width below \(Int(info.minimumBodyDiameterMillimeters)) mm")
        }
        if flight.rocketMassGrams > info.maxLiftOffMassGrams {
            reasons.append("lift-off mass above \(Int(info.maxLiftOffMassGrams)) g")
        }
        if !MotorCatalog.competitionMotors.contains(where: { $0.designation == flight.motorDesignation }) {
            reasons.append("motor not on approved ARC list")
        }

        let targetAltitude = scoringTargetAltitude(for: flight)
        let altitudePoints = Int(abs(flight.measuredAltitudeFeet - targetAltitude).rounded())
        let timePoints: Int
        if let flightTimeSeconds = flight.flightTimeSeconds {
            if info.flightTimeRange.contains(flightTimeSeconds) {
                timePoints = 0
            } else if flightTimeSeconds < info.flightTimeRange.lowerBound {
                timePoints = Int(((info.flightTimeRange.lowerBound - flightTimeSeconds) * 4).rounded())
            } else {
                timePoints = Int(((flightTimeSeconds - info.flightTimeRange.upperBound) * 4).rounded())
            }
        } else {
            timePoints = 0
        }

        return FlightScoreSummary(
            isDisqualified: !reasons.isEmpty,
            disqualificationReasons: reasons,
            altitudePoints: altitudePoints,
            timePoints: timePoints
        )
    }

    func bestScoredFlights(limit: Int) -> [Flight] {
        flights
            .filter { ($0.round ?? "") != FlightMode.hobby.shortTitle }
            .sorted {
                let left = scoreSummary(for: $0)
                let right = scoreSummary(for: $1)
                switch (left.totalPoints, right.totalPoints) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return $0.flownAt > $1.flownAt
                }
            }
            .prefix(limit)
            .map { $0 }
    }

    func scoringTargetAltitude(for flight: Flight) -> Double {
        if (flight.round ?? "") == FlightMode.nationals.shortTitle,
           let target = flight.targetAltitudeFeet,
           target.isFinite {
            return target
        }
        return syncedCompetitionInfo.altitudeGoalFeet
    }

    func restartLaunchWindow(duration: Int = 45 * 60) {
        launchWindowSeconds = duration
        launchWindowEndsAt = Date().addingTimeInterval(TimeInterval(duration))
        launchTimerState = .running
        save(immediate: true)
    }

    func startLaunchWindow() {
        if launchWindowRemaining() <= 0 {
            launchWindowSeconds = 45 * 60
        }
        launchWindowEndsAt = Date().addingTimeInterval(TimeInterval(launchWindowSeconds))
        launchTimerState = .running
        save(immediate: true)
    }

    func pauseLaunchWindow(now: Date = Date()) {
        launchWindowSeconds = launchWindowRemaining(at: now)
        launchWindowEndsAt = nil
        launchTimerState = .paused
        save(immediate: true)
    }

    func stopLaunchWindow(duration: Int = 45 * 60) {
        launchWindowSeconds = duration
        launchWindowEndsAt = nil
        launchTimerState = .stopped
        save(immediate: true)
    }

    func syncLaunchWindowRemaining(now: Date = Date()) {
        guard launchTimerState == .running, let launchWindowEndsAt else {
            return
        }
        launchWindowSeconds = max(0, Int(ceil(launchWindowEndsAt.timeIntervalSince(now))))
        if launchWindowSeconds == 0 {
            self.launchWindowEndsAt = nil
            launchTimerState = .stopped
            save(immediate: true)
        }
    }

    func launchWindowRemaining(at date: Date = Date()) -> Int {
        guard launchTimerState == .running, let launchWindowEndsAt else {
            return launchWindowSeconds
        }
        return max(0, Int(ceil(launchWindowEndsAt.timeIntervalSince(date))))
    }

    func addLaunchChecklistItem(_ title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        launchChecklistItems.append(LaunchChecklistItem(title: trimmedTitle))
        save()
    }

    func updateLaunchChecklistItem(id: UUID, title: String) {
        guard let index = launchChecklistItems.firstIndex(where: { $0.id == id }) else { return }
        launchChecklistItems[index].title = title
        save()
    }

    func toggleLaunchChecklistItem(id: UUID) {
        guard let index = launchChecklistItems.firstIndex(where: { $0.id == id }) else { return }
        launchChecklistItems[index].isComplete.toggle()
        save()
    }

    func deleteLaunchChecklistItem(id: UUID) {
        launchChecklistItems.removeAll { $0.id == id }
        save()
    }

    func save(immediate: Bool = false) {
        let snapshot = currentSnapshot()
        let key = storageKey
        pendingSaveTask?.cancel()
        if immediate {
            if let data = try? JSONEncoder.arc.encode(snapshot) {
                UserDefaults.standard.set(data, forKey: key)
            }
            return
        }
        pendingSaveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder.arc.encode(snapshot) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }

    private func currentSnapshot() -> StoreSnapshot {
        let snapshot = StoreSnapshot(
            teams: teams,
            rockets: rockets,
            flights: flights,
            flightMode: flightMode,
            targetAltitudeFeet: targetAltitudeFeet,
            launchWindowSeconds: launchWindowSeconds,
            launchWindowEndsAt: launchWindowEndsAt,
            launchTimerState: launchTimerState,
            launchChecklistItems: launchChecklistItems,
            profile: profile,
            personalAccount: personalAccount,
            syncedCompetitionInfo: syncedCompetitionInfo,
            nationalsLookup: nationalsLookup,
            cloudSyncSettings: cloudSyncSettings
        )
        return snapshot
    }

    private func applySnapshot(_ snapshot: StoreSnapshot) {
        teams = snapshot.teams
        rockets = snapshot.rockets
        flights = snapshot.flights
        flightMode = snapshot.flightMode ?? (snapshot.nationalsMode == true ? .nationals : .hobby)
        targetAltitudeFeet = snapshot.targetAltitudeFeet
        launchWindowSeconds = snapshot.launchWindowSeconds
        launchWindowEndsAt = snapshot.launchWindowEndsAt
        launchTimerState = snapshot.launchTimerState ?? (snapshot.launchWindowEndsAt == nil ? .stopped : .running)
        launchChecklistItems = snapshot.launchChecklistItems?.isEmpty == false
            ? snapshot.launchChecklistItems ?? Self.defaultLaunchChecklistItems
            : Self.defaultLaunchChecklistItems
        syncLaunchWindowRemaining()
        profile = snapshot.profile ?? UserProfile()
        personalAccount = snapshot.personalAccount ?? PersonalAccount()
        syncedCompetitionInfo = snapshot.syncedCompetitionInfo ?? MotorCatalog.arc2026CompetitionInfo
        nationalsLookup = sanitizedNationalsLookup(snapshot.nationalsLookup)
        cloudSyncSettings = snapshot.cloudSyncSettings ?? CloudSyncSettings()
        if flightMode == .nationals && !hasNationalsAccess {
            flightMode = .competition
            targetAltitudeFeet = syncedCompetitionInfo.altitudeGoalFeet
        }
    }

    private func mergeSnapshot(_ snapshot: StoreSnapshot) -> (teams: Int, rockets: Int, flights: Int) {
        let teamIDs = Set(teams.map(\.id))
        let rocketIDs = Set(rockets.map(\.id))
        let flightIDs = Set(flights.map(\.id))
        let newTeams = snapshot.teams.filter { !teamIDs.contains($0.id) }
        let newRockets = snapshot.rockets.filter { !rocketIDs.contains($0.id) }
        let newFlights = snapshot.flights.filter { !flightIDs.contains($0.id) }
        teams.append(contentsOf: newTeams)
        rockets.append(contentsOf: newRockets)
        flights.append(contentsOf: newFlights)
        flights.sort { $0.flownAt > $1.flownAt }

        if profile.schoolOrganization.isEmpty, let importedProfile = snapshot.profile {
            profile = importedProfile
        }
        if !personalAccount.isRegistered, let importedAccount = snapshot.personalAccount {
            personalAccount = importedAccount
        }
        if let info = snapshot.syncedCompetitionInfo, info.seasonYear >= syncedCompetitionInfo.seasonYear {
            syncedCompetitionInfo = info
        }
        if nationalsLookup == nil {
            nationalsLookup = sanitizedNationalsLookup(snapshot.nationalsLookup)
        }
        return (newTeams.count, newRockets.count, newFlights.count)
    }

    private func load() {
        if
            let data = UserDefaults.standard.data(forKey: storageKey),
            let snapshot = try? JSONDecoder.arc.decode(StoreSnapshot.self, from: data)
        {
            applySnapshot(snapshot)
            save()
            return
        }

        teams = []
        rockets = []
        flights = []
        save()
    }

    func updateProfile(schoolOrganization: String, teamNumber: String, teamName: String) {
        profile = UserProfile(
            schoolOrganization: schoolOrganization,
            teamNumber: teamNumber,
            teamName: teamName
        )
        save()
    }

    func registerAccount(displayName: String, email: String) {
        personalAccount = PersonalAccount(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            registeredAt: personalAccount.registeredAt
        )

        if personalAccount.isRegistered, let teamID = teams.first?.id {
            ensureAccountMember(on: teamID)
        }
        save()
    }

    func updateTeamWorkspace(teamID: UUID, name: String, school: String) {
        guard let index = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Team" : name
        teams[index].school = school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Independent" : school
        save()
    }

    func addTeamMember(teamID: UUID, name: String, email: String) {
        guard let index = teams.firstIndex(where: { $0.id == teamID }) else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty || !trimmedEmail.isEmpty else { return }
        teams[index].members.append(
            TeamMember(
                name: trimmedName.isEmpty ? "Teammate" : trimmedName,
                email: trimmedEmail,
                role: "Member"
            )
        )
        save()
    }

    func joinTeam(withCode code: String) -> String {
        let normalizedCode = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard personalAccount.isRegistered else {
            return "Register your name and email before joining a team."
        }
        guard !normalizedCode.isEmpty else {
            return "Enter a team join code."
        }
        guard let index = teams.firstIndex(where: { $0.joinCode.uppercased() == normalizedCode }) else {
            return "No team was found for that join code."
        }

        ensureAccountMember(on: teams[index].id)
        let joinedTeam = teams.remove(at: index)
        teams.insert(joinedTeam, at: 0)
        save()
        return "Joined \(joinedTeam.name)."
    }

    func removeTeamMember(teamID: UUID, memberID: UUID) {
        guard let index = teams.firstIndex(where: { $0.id == teamID }) else { return }
        teams[index].members.removeAll { $0.id == memberID }
        save()
    }

    private func ensureAccountMember(on teamID: UUID) {
        guard personalAccount.isRegistered, let index = teams.firstIndex(where: { $0.id == teamID }) else { return }
        if teams[index].members.contains(where: { $0.email.caseInsensitiveCompare(personalAccount.email) == .orderedSame }) {
            return
        }
        teams[index].members.insert(
            TeamMember(name: personalAccount.displayName, email: personalAccount.email, role: "Owner"),
            at: 0
        )
    }

    func updateCompetitionInfo(_ info: ARCCompetitionInfo) {
        syncedCompetitionInfo = info
        if isCompetitionMode {
            targetAltitudeFeet = info.altitudeGoalFeet
        }
        save()
    }

    func updateCompetitionInfoManually(
        altitudeGoalFeet: Double,
        timeLow: Double,
        timeHigh: Double,
        maxMass: Double,
        minLength: Double,
        minDiameter: Double,
        qualificationWindow: String,
        finalsDate: String,
        finalsLocation: String
    ) {
        syncedCompetitionInfo = ARCCompetitionInfo(
            seasonYear: syncedCompetitionInfo.seasonYear,
            sourceName: "Manual ARC settings",
            sourceUpdated: "Updated manually",
            lastCheckedAt: Date(),
            altitudeGoalFeet: altitudeGoalFeet,
            flightTimeRange: min(timeLow, timeHigh)...max(timeLow, timeHigh),
            maxLiftOffMassGrams: maxMass,
            minimumLengthMillimeters: minLength,
            minimumBodyDiameterMillimeters: minDiameter,
            qualificationWindow: qualificationWindow,
            finalsDate: finalsDate,
            finalsLocation: finalsLocation
        )
        if isCompetitionMode {
            targetAltitudeFeet = altitudeGoalFeet
        }
        save()
    }

    func configureCloudSync(enabled: Bool, providerName: String, workspaceID: String) {
        cloudSyncSettings = CloudSyncSettings(
            enabled: enabled,
            providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "iCloud" : providerName,
            workspaceID: workspaceID.trimmingCharacters(in: .whitespacesAndNewlines),
            lastSyncAt: enabled ? Date() : cloudSyncSettings.lastSyncAt
        )
        save()
    }

    func saveToICloud() -> String {
        guard let data = try? JSONEncoder.arc.encode(currentSnapshot()) else {
            return "Could not prepare the logbook for iCloud."
        }
        let keyValueStore = NSUbiquitousKeyValueStore.default
        keyValueStore.set(data, forKey: iCloudStorageKey)
        keyValueStore.synchronize()
        cloudSyncSettings = CloudSyncSettings(
            enabled: true,
            providerName: "iCloud",
            workspaceID: personalAccount.email.isEmpty ? "RocketTune" : personalAccount.email,
            lastSyncAt: Date()
        )
        save()
        return "Saved this logbook to iCloud."
    }

    func loadFromICloud() -> String {
        let keyValueStore = NSUbiquitousKeyValueStore.default
        keyValueStore.synchronize()
        guard
            let data = keyValueStore.data(forKey: iCloudStorageKey),
            let snapshot = try? JSONDecoder.arc.decode(StoreSnapshot.self, from: data)
        else {
            return "No RocketTune logbook was found in iCloud for this Apple ID."
        }
        applySnapshot(snapshot)
        cloudSyncSettings.enabled = true
        cloudSyncSettings.providerName = "iCloud"
        cloudSyncSettings.lastSyncAt = Date()
        save()
        return "Loaded the iCloud logbook onto this iPhone."
    }

    func exportTeamBackupText() -> String {
        guard let data = try? JSONEncoder.arc.encode(currentSnapshot()),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    func importTeamBackupText(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let snapshot = try? JSONDecoder.arc.decode(StoreSnapshot.self, from: data) else {
            return "Could not read that team backup."
        }
        let merged = mergeSnapshot(snapshot)
        save()
        return "Merged team backup: \(merged.teams) teams, \(merged.rockets) rockets, and \(merged.flights) flights added."
    }

    var nationalsPlanningRange: ClosedRange<Double> {
        let target = syncedCompetitionInfo.altitudeGoalFeet
        let lowerBound = max(100, target - 50)
        let upperBound = target + 50
        return lowerBound...upperBound
    }

    var shouldRefreshCompetitionInfo: Bool {
        syncedCompetitionInfo.seasonYear < currentSeasonYear
    }

    var currentSeasonYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    func refreshCompetitionInfoIfNeeded() async {
        guard shouldRefreshCompetitionInfo, !didAttemptAutomaticSync else { return }
        didAttemptAutomaticSync = true

        do {
            let info = try await ARCWebsiteService.syncCompetitionInfo()
            updateCompetitionInfo(info)
        } catch {
            // Keep the last good season snapshot when the network is unavailable.
        }
    }

    func updateNationalsLookup(_ result: NationalsLookupResult?) {
        nationalsLookup = sanitizedNationalsLookup(result)
        if flightMode == .nationals && !hasNationalsAccess {
            flightMode = .competition
            targetAltitudeFeet = syncedCompetitionInfo.altitudeGoalFeet
        }
        save()
    }

    private func sanitizedNationalsLookup(_ result: NationalsLookupResult?) -> NationalsLookupResult? {
        guard let result else { return nil }
        return NationalsLookupResult(
            status: result.status,
            seasonYear: result.seasonYear,
            message: result.message.arcPlainText,
            matchedName: result.matchedName?.arcPlainText,
            sourceURL: result.sourceURL
        )
    }
}

private struct StoreSnapshot: Codable {
    var teams: [Team]
    var rockets: [Rocket]
    var flights: [Flight]
    var flightMode: FlightMode?
    var targetAltitudeFeet: Double
    var nationalsMode: Bool?
    var launchWindowSeconds: Int
    var launchWindowEndsAt: Date?
    var launchTimerState: LaunchTimerState?
    var launchChecklistItems: [LaunchChecklistItem]?
    var profile: UserProfile?
    var personalAccount: PersonalAccount?
    var syncedCompetitionInfo: ARCCompetitionInfo?
    var nationalsLookup: NationalsLookupResult?
    var cloudSyncSettings: CloudSyncSettings?
}

extension JSONEncoder {
    static var arc: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var arc: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
