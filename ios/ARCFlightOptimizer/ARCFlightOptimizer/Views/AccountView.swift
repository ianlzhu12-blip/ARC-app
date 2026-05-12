import SwiftUI
import UniformTypeIdentifiers
import Compression

struct AccountView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var displayName = ""
    @State private var email = ""
    @State private var schoolOrganization = ""
    @State private var teamNumber = ""
    @State private var teamName = ""
    @State private var joinCode = ""
    @State private var teammateName = ""
    @State private var teammateEmail = ""
    @State private var statusMessage = ""
    @State private var isSyncingRules = false
    @State private var isCheckingNationals = false
    @State private var isExportingFlightSheet = false
    @State private var isImportingFlightSheet = false
    @State private var isExportingTeamBackup = false
    @State private var isImportingTeamBackup = false
    @State private var cloudEnabled = false
    @State private var attachedSheetNames: [String] = []
    @State private var overrideAltitude = 750.0
    @State private var overrideTimeLow = 36.0
    @State private var overrideTimeHigh = 39.0
    @State private var overrideMaxMass = 650.0
    @State private var overrideMinLength = 650.0
    @State private var overrideMinDiameter = 47.0
    @State private var overrideQualificationWindow = ""
    @State private var overrideFinalsDate = ""
    @State private var overrideFinalsLocation = ""
    @State private var showManualOverrides = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    accountCard
                    statusCard
                    profileCard
                    teamWorkspaceCard
                    cloudSyncCard
                    dataPortabilityCard
                    rulesSyncCard
                    nationalsStatusCard
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                displayName = store.personalAccount.displayName
                email = store.personalAccount.email
                schoolOrganization = store.profile.schoolOrganization
                teamNumber = store.profile.teamNumber
                teamName = store.profile.teamName
                cloudEnabled = store.cloudSyncSettings.enabled
                primeManualRuleFields()
            }
            .task {
                await store.refreshCompetitionInfoIfNeeded()
            }
            .fileExporter(
                isPresented: $isExportingFlightSheet,
                document: FlightSheetDocument(text: exportFlightSheet()),
                contentType: .plainText,
                defaultFilename: "RocketTune Flight Sheet.tsv"
            ) { result in
                if case .success = result {
                    statusMessage = "Saved flight sheet."
                }
            }
            .sheet(isPresented: $isImportingFlightSheet) {
                FlightSheetPicker(allowedContentTypes: flightSheetTypes) { result in
                    isImportingFlightSheet = false
                    importFlightSheets(result)
                }
            }
            .fileExporter(
                isPresented: $isExportingTeamBackup,
                document: FlightSheetDocument(text: store.exportTeamBackupText()),
                contentType: .json,
                defaultFilename: "RocketTune Team Backup.json"
            ) { result in
                if case .success = result {
                    statusMessage = "Saved team backup."
                }
            }
            .fileImporter(
                isPresented: $isImportingTeamBackup,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                importTeamBackup(result)
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        if !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.arcMint)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var activeTeam: Team? {
        store.teams.first
    }

    private var hasAddedTeamMembers: Bool {
        guard let activeTeam else { return false }
        return activeTeam.members.contains { $0.role.caseInsensitiveCompare("Owner") != .orderedSame }
    }

    private var flightSheetTypes: [UTType] {
        let types: [UTType?] = [
            UTType(filenameExtension: "xlsx"),
            UTType(filenameExtension: "xls"),
            UTType(filenameExtension: "numbers"),
            UTType(filenameExtension: "csv"),
            UTType(filenameExtension: "tsv"),
            UTType(filenameExtension: "txt"),
            UTType("org.openxmlformats.spreadsheetml.sheet"),
            UTType("com.microsoft.excel.xls"),
            UTType("com.microsoft.excel.xlsx"),
            UTType("com.apple.iwork.numbers.numbers"),
            UTType("public.spreadsheet"),
            .commaSeparatedText,
            .tabSeparatedText,
            .text,
            .plainText,
            .content,
            .item,
            .data
        ]
        return types.compactMap { $0 }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal Account")
                .font(.title3.bold())
            Text("Register your name so flights and team data can be grouped under the same workspace.")
                .foregroundStyle(.secondary)
            TextField("Your name", text: $displayName)
                .textInputAutocapitalization(.words)
                .fieldStyle()
            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .fieldStyle()
            Button(store.personalAccount.isRegistered ? "Update Account" : "Register Account") {
                store.registerAccount(displayName: displayName, email: email)
                statusMessage = store.personalAccount.isRegistered ? "Account saved." : "Add your name and email to register."
            }
            .buttonStyle(.borderedProminent)

            Divider()
                .overlay(.white.opacity(0.18))

            Text("Join a Team")
                .font(.headline)
            Text("Ask a teammate for their team join code, then enter it here to share the same practice workspace.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Team join code", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .fieldStyle()
            Button {
                statusMessage = store.joinTeam(withCode: joinCode)
                if statusMessage.hasPrefix("Joined") {
                    joinCode = ""
                }
            } label: {
                Label("Join Team", systemImage: "person.2.badge.gearshape.fill")
            }
            .buttonStyle(.bordered)
            .disabled(!store.personalAccount.isRegistered)
        }
        .cardStyle()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Profile")
                .font(.title3.bold())
            TextField("School / organization", text: $schoolOrganization)
                .fieldStyle()
            TextField("Team number", text: $teamNumber)
                .fieldStyle()
            TextField("Team name (recommended for nationals lookup)", text: $teamName)
                .fieldStyle()
            Button("Save Profile") {
                store.updateProfile(
                    schoolOrganization: schoolOrganization,
                    teamNumber: teamNumber,
                    teamName: teamName
                )
                if let activeTeam {
                    store.updateTeamWorkspace(teamID: activeTeam.id, name: teamName, school: schoolOrganization)
                }
                statusMessage = "Saved profile."
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle()
    }

    private var teamWorkspaceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Team Data Workspace")
                .font(.title3.bold())
            Text("Rockets and flights are grouped by team so teammates using this shared workspace can pile up practice data together.")
                .foregroundStyle(.secondary)

            if let activeTeam {
                Text("Team: \(activeTeam.name)")
                    .font(.headline)
                Text("Join code: \(activeTeam.joinCode)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.arcMint)
                Text("School: \(activeTeam.school)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Members")
                        .font(.headline)
                    if activeTeam.members.isEmpty {
                        Text("No team members added yet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeTeam.members) { member in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.subheadline.weight(.semibold))
                                    if !member.email.isEmpty {
                                        Text(member.email)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(member.role)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.arcAmber)
                                Button(role: .destructive) {
                                    store.removeTeamMember(teamID: activeTeam.id, memberID: member.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(10)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }

                TextField("Teammate name", text: $teammateName)
                    .textInputAutocapitalization(.words)
                    .fieldStyle()
                TextField("Teammate email", text: $teammateEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    .fieldStyle()
                Button {
                    store.addTeamMember(teamID: activeTeam.id, name: teammateName, email: teammateEmail)
                    teammateName = ""
                    teammateEmail = ""
                    statusMessage = "Added teammate."
                } label: {
                    Label("Add Teammate", systemImage: "person.badge.plus")
                }
                .buttonStyle(.bordered)
            } else {
                Text("Create a team from Teams & Rockets to start collecting shared data.")
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var cloudSyncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("iCloud Sync")
                .font(.title3.bold())
            Text("When your personal account is registered and iCloud sync is on, RocketTune automatically saves changes and merges data from your other Apple devices.")
                .foregroundStyle(.secondary)
            Toggle("Use iCloud for this logbook", isOn: $cloudEnabled)

            VStack(spacing: 10) {
                Button {
                    store.configureCloudSync(enabled: cloudEnabled, providerName: "iCloud", workspaceID: store.personalAccount.email)
                    statusMessage = cloudEnabled
                        ? "Auto sync is on. New flights, edits, rockets, and account changes will sync through iCloud."
                        : "iCloud auto sync is off."
                } label: {
                    Label("Save iCloud Setting", systemImage: "icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 10) {
                    Button {
                        statusMessage = store.saveToICloud()
                        cloudEnabled = store.cloudSyncSettings.enabled
                    } label: {
                        Label("Save", systemImage: "icloud.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        statusMessage = store.loadFromICloud()
                        cloudEnabled = store.cloudSyncSettings.enabled
                        primeManualRuleFields()
                    } label: {
                        Label("Load", systemImage: "icloud.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Text(store.cloudSyncSettings.statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !store.personalAccount.isRegistered {
                Text("Register your personal account above before automatic sync starts.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcAmber)
            }
        }
        .cardStyle()
    }

    private var dataPortabilityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Flight Sheet Attachments")
                .font(.title3.bold())
            Text("Attach an Excel, Numbers, or spreadsheet text file from Files. The app converts readable flight rows into editable logs.")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                if hasAddedTeamMembers {
                    Button {
                        isExportingTeamBackup = true
                    } label: {
                        Label("Export Team Backup", systemImage: "person.3.sequence.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isImportingTeamBackup = true
                    } label: {
                        Label("Import Team Backup", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    isImportingFlightSheet = true
                } label: {
                    Label("Attach and Import Sheet", systemImage: "paperclip")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(item: exportFlightSheet()) {
                    Label("Share Flight Sheet", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !attachedSheetNames.isEmpty {
                    ForEach(attachedSheetNames, id: \.self) { name in
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var rulesSyncCard: some View {
        let season = String(store.syncedCompetitionInfo.seasonYear)
        return VStack(alignment: .leading, spacing: 12) {
            Text("ARC Website Sync")
                .font(.title3.bold())
            Text("Pull the current competition year and requirements from rocketrychallenge.org so Competition and Nationals update each season.")
                .foregroundStyle(.secondary)
            Text(verbatim: "Current synced season: \(season)")
                .font(.headline)
            Text("Last checked: \(store.syncedCompetitionInfo.lastCheckedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Current synced source: \(store.syncedCompetitionInfo.sourceUpdated.arcPlainText)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if store.shouldRefreshCompetitionInfo {
                Text("A newer ARC season may be available. Sync to refresh the app’s competition and Nationals settings.")
                    .font(.footnote)
                    .foregroundStyle(Color.arcAmber)
            }
            Button {
                Task { await syncRules() }
            } label: {
                if isSyncingRules {
                    ProgressView()
                } else {
                    Label("Sync Current ARC Requirements", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)

            Divider()
                .overlay(.white.opacity(0.18))

            manualRulesContent
        }
        .cardStyle()
    }

    private var manualRulesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARC Overrides")
                        .font(.title3.bold())
                    Text("Only use these if you need to manually change competition rules.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(showManualOverrides ? "Hide" : "Override") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showManualOverrides.toggle()
                    }
                }
                .buttonStyle(.bordered)
            }

            if showManualOverrides {
                NumberField(title: "Target Altitude", value: $overrideAltitude, suffix: "ft")
                HStack {
                    NumberField(title: "Time Low", value: $overrideTimeLow, suffix: "s")
                    NumberField(title: "Time High", value: $overrideTimeHigh, suffix: "s")
                }
                NumberField(title: "Max Lift-off Mass", value: $overrideMaxMass, suffix: "g")
                HStack {
                    NumberField(title: "Min Length", value: $overrideMinLength, suffix: "mm")
                    NumberField(title: "Min Diameter", value: $overrideMinDiameter, suffix: "mm")
                }
                TextField("Qualification window", text: $overrideQualificationWindow)
                    .fieldStyle()
                TextField("Finals date", text: $overrideFinalsDate)
                    .fieldStyle()
                TextField("Finals location", text: $overrideFinalsLocation)
                    .fieldStyle()
                Button {
                    store.updateCompetitionInfoManually(
                        altitudeGoalFeet: overrideAltitude,
                        timeLow: overrideTimeLow,
                        timeHigh: overrideTimeHigh,
                        maxMass: overrideMaxMass,
                        minLength: overrideMinLength,
                        minDiameter: overrideMinDiameter,
                        qualificationWindow: overrideQualificationWindow,
                        finalsDate: overrideFinalsDate,
                        finalsLocation: overrideFinalsLocation
                    )
                    statusMessage = "Saved manual ARC settings."
                } label: {
                    Label("Save Manual Settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var nationalsStatusCard: some View {
        let season = String(store.syncedCompetitionInfo.seasonYear)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Nationals Status")
                .font(.title3.bold())
            Text("Checks the public ARC finalists page using your school/organization and optional team name. ARC public results pages do not usually publish numeric team IDs.")
                .foregroundStyle(.secondary)
            Button {
                Task { await lookupNationals() }
            } label: {
                if isCheckingNationals {
                    ProgressView()
                } else {
                    Label {
                        Text(verbatim: "Check \(season) Nationals")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            if let result = store.nationalsLookup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(result.status.displayTitle)
                        .font(.headline)
                    Text(result.displayMessage)
                    Text(store.hasNationalsAccess ? "Nationals Mode is unlocked." : "Nationals Mode remains locked until this check confirms your team made Nationals.")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(store.hasNationalsAccess ? Color.arcMint : Color.arcAmber)
                    if let matchedName = result.displayMatchedName {
                        Text("Matched team: \(matchedName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let source = URL(string: result.sourceURL) {
                        Link("View ARC finalist source", destination: source)
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
        .cardStyle()
    }

    private func syncRules() async {
        isSyncingRules = true
        defer { isSyncingRules = false }
        do {
            let info = try await ARCWebsiteService.syncCompetitionInfo()
            store.updateCompetitionInfo(info)
            primeManualRuleFields()
            statusMessage = "Synced ARC requirements."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func lookupNationals() async {
        isCheckingNationals = true
        defer { isCheckingNationals = false }
        let year = store.syncedCompetitionInfo.seasonYear
        do {
            let result = try await ARCWebsiteService.lookupNationals(profile: store.profile, seasonYear: year)
            store.updateNationalsLookup(result)
        } catch {
            store.updateNationalsLookup(
                NationalsLookupResult(
                    status: .lookupFailed,
                    seasonYear: year,
                    message: error.localizedDescription,
                    matchedName: nil,
                    sourceURL: "https://www.rocketrychallenge.org/result/\(year)-finalists/"
                )
            )
        }
    }

    private func primeManualRuleFields() {
        let info = store.syncedCompetitionInfo
        overrideAltitude = info.altitudeGoalFeet
        overrideTimeLow = info.flightTimeRange.lowerBound
        overrideTimeHigh = info.flightTimeRange.upperBound
        overrideMaxMass = info.maxLiftOffMassGrams
        overrideMinLength = info.minimumLengthMillimeters
        overrideMinDiameter = info.minimumBodyDiameterMillimeters
        overrideQualificationWindow = info.qualificationWindow.arcPlainText
        overrideFinalsDate = info.finalsDate.arcPlainText
        overrideFinalsLocation = info.finalsLocation.arcPlainText
    }

    private func exportFlightSheet() -> String {
        var rows = ["Date\tRocket\tMotor\tMass g\tWanted altitude ft\tAltitude ft\tFlight time s\tTemperature F\tWind mph\tHumidity %\tParachute in\tReefed cm\tEgg\tNotes\tAttachments"]
        for flight in store.flights {
            let rocketName = store.rocket(for: flight)?.name ?? "Unknown Rocket"
            let fields = [
                flight.flownAt.formatted(date: .numeric, time: .shortened),
                rocketName,
                flight.motorDesignation,
                formattedGrams(flight.rocketMassGrams),
                flight.targetAltitudeFeet.map { "\(Int($0))" } ?? "",
                "\(Int(flight.measuredAltitudeFeet))",
                flight.flightTimeSeconds.map { String(format: "%.1f", $0) } ?? "",
                "\(Int(flight.weather.temperatureF))",
                "\(Int(flight.weather.windMPH))",
                "\(Int(flight.weather.humidityPercent))",
                "\(Int(flight.parachuteSizeInches))",
                flight.parachuteReefedCentimeters.map { String(format: "%.1f", $0) } ?? "",
                flight.eggStatus.displayName,
                flight.notes,
                flight.attachments.map(\.fileName).joined(separator: " | ")
            ]
            rows.append(fields.map(sheetEscape).joined(separator: "\t"))
        }
        return rows.joined(separator: "\n")
    }

    private func importFlightSheets(_ result: Result<[URL], Error>) {
        isImportingFlightSheet = false
        statusMessage = "Importing sheet attachments..."
        Task {
            await importFlightSheetsAsync(result)
        }
    }

    private func importTeamBackup(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else {
            statusMessage = "Could not open that team backup."
            return
        }
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            statusMessage = store.importTeamBackupText(text)
        } catch {
            statusMessage = "Could not read that team backup."
        }
    }

    private func importFlightSheetsAsync(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            guard !urls.isEmpty else {
                statusMessage = "No sheet was selected."
                return
            }
            guard !store.rockets.isEmpty else {
                statusMessage = "Create a rocket first, then import a flight sheet so imported flights have a rocket to attach to."
                return
            }

            var importedCount = 0
            var localImportedCount = 0
            var replacedImportedCount = 0
            var attachedOnly: [String] = []
            var unreadableFiles: [String] = []
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let fileName = url.lastPathComponent
                guard let data = try? importedFileData(from: url) else {
                    unreadableFiles.append(fileName)
                    continue
                }
                if !attachedSheetNames.contains(fileName) {
                    attachedSheetNames.append(fileName)
                }
                let sheetTexts = spreadsheetTexts(from: data, fileName: fileName)
                guard !sheetTexts.isEmpty else {
                    attachedOnly.append(fileName)
                    continue
                }
                let flights = sheetTexts.flatMap { sheetText in
                    parseFlightSheet(sheetText.text, fileName: sheetText.name)
                }
                if flights.isEmpty {
                    attachedOnly.append(fileName)
                } else {
                    localImportedCount += flights.count
                    importedCount += flights.count
                    let sourceNames = Set(sheetTexts.map(\.name) + [fileName])
                    let replacement = store.replaceImportedFlights(flights, sourceNames: sourceNames)
                    replacedImportedCount += replacement.removed
                }
            }
            if importedCount > 0 {
                let replacementText = replacedImportedCount > 0 ? " Replaced \(replacedImportedCount) older import(s) from the same sheet." : ""
                statusMessage = "Imported \(localImportedCount) editable flight logs after multi-pass checks.\(replacementText) They now feed graphs, summaries, and weight calculations."
            } else if !unreadableFiles.isEmpty {
                statusMessage = "Could not read \(unreadableFiles.count) selected file(s). Try saving the sheet to Files as .xlsx, .csv, or tab-separated text, then import again."
            } else if !attachedOnly.isEmpty {
                statusMessage = "Attached \(attachedOnly.count) file(s), but no readable flight rows were found. Excel .xlsx, CSV, and tab-separated sheets work best."
            } else {
                statusMessage = "No flight rows were found in the attached sheets."
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func importedFileData(from url: URL) throws -> Data {
        var coordinatorError: NSError?
        var readResult: Result<Data, Error>?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { coordinatedURL in
            readResult = Result {
                try Data(contentsOf: coordinatedURL)
            }
        }
        if let readResult {
            return try readResult.get()
        }
        if let coordinatorError {
            throw coordinatorError
        }
        return try Data(contentsOf: url)
    }

    private func parseFlightSheet(_ text: String, fileName: String) -> [Flight] {
        guard let fallbackRocket = store.rockets.first else { return [] }
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return [] }
        let delimiter = detectedDelimiter(in: Array(lines.prefix(12)))
        let rows = lines.map { parseDelimitedLine($0, delimiter: delimiter) }
        guard let headerRowIndex = inferredHeaderRowIndex(in: rows) else { return [] }
        let headers = rows[headerRowIndex]
        let dataRows = Array(rows.dropFirst(headerRowIndex + 1))
        let columnMap = inferredColumnMap(headers: headers, rows: dataRows)

        let parsedFlights: [Flight] = rows.dropFirst(headerRowIndex + 1).enumerated().compactMap { rowOffset, columns -> Flight? in
            guard !isLikelyHeaderOrEmptyRow(columns, headers: headers) else { return nil }
            guard let altitudeText = value(in: columns, columnMap: columnMap, role: .altitude),
                  let altitude = plausibleSheetNumber(
                    altitudeText,
                    role: .altitude,
                    header: header(for: .altitude, headers: headers, columnMap: columnMap),
                    defaultUnit: .feet
                  )
            else { return nil }

            let rocketName = value(in: columns, columnMap: columnMap, role: .rocket) ?? fallbackRocket.name
            let rocket = matchedRocket(named: rocketName) ?? fallbackRocket
            let motor = normalizedMotorDesignation(value(in: columns, columnMap: columnMap, role: .motor)) ?? rocket.defaultMotorDesignation
            let massText = value(in: columns, columnMap: columnMap, role: .mass)
            let parsedMass = massText.flatMap {
                plausibleSheetNumber(
                    $0,
                    role: .mass,
                    header: header(for: .mass, headers: headers, columnMap: columnMap),
                    defaultUnit: .grams
                )
            }
            let mass = parsedMass ?? rocket.dryMassGrams + 90
            let rowNotes = value(in: columns, columnMap: columnMap, role: .notes) ?? ""
            let targetAltitude = value(in: columns, columnMap: columnMap, role: .targetAltitude)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .targetAltitude,
                        header: header(for: .targetAltitude, headers: headers, columnMap: columnMap),
                        defaultUnit: .feet
                    )
                }
                ?? inferredTargetAltitude(from: [rocketName, rowNotes])
            guard isReasonableImportedAltitude(altitude, targetAltitude: targetAltitude) else {
                return nil
            }
            let time = value(in: columns, columnMap: columnMap, role: .time)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .time,
                        header: header(for: .time, headers: headers, columnMap: columnMap),
                        defaultUnit: .seconds
                    )
                }
            let temp = value(in: columns, columnMap: columnMap, role: .temperature)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .temperature,
                        header: header(for: .temperature, headers: headers, columnMap: columnMap),
                        defaultUnit: .fahrenheit
                    )
                }
                ?? 72
            let wind = value(in: columns, columnMap: columnMap, role: .wind)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .wind,
                        header: header(for: .wind, headers: headers, columnMap: columnMap),
                        defaultUnit: .mph
                    )
                }
                ?? 0
            let humidity = value(in: columns, columnMap: columnMap, role: .humidity)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .humidity,
                        header: header(for: .humidity, headers: headers, columnMap: columnMap),
                        defaultUnit: .percent
                    )
                }
                ?? 45
            let chute = value(in: columns, columnMap: columnMap, role: .parachute)
                .flatMap {
                    plausibleSheetNumber(
                        $0,
                        role: .parachute,
                        header: header(for: .parachute, headers: headers, columnMap: columnMap),
                        defaultUnit: .inches
                    )
                }
                ?? rocket.parachuteSizeInches
            let reefedFromName = inferredReefedCentimeters(from: [rocketName, fileName], allowsBareCentimeterName: true)
            let reefedCentimeters = reefedFromName
                ?? value(in: columns, columnMap: columnMap, role: .reefedCentimeters)
                .flatMap {
                    plausibleReefedCentimeters(
                        $0,
                        header: header(for: .reefedCentimeters, headers: headers, columnMap: columnMap)
                    )
                }
                ?? inferredReefedCentimeters(from: [rowNotes])
            let weatherConditions = value(in: columns, columnMap: columnMap, role: .weatherConditions)
            let recoveryBlanket = value(in: columns, columnMap: columnMap, role: .recoveryBlanket)
            let importedPoints = value(in: columns, columnMap: columnMap, role: .importedPoints)
            let dateText = value(in: columns, columnMap: columnMap, role: .date)
            let date = dateText.flatMap(sheetDate) ?? Date()
            let eggText = value(in: columns, columnMap: columnMap, role: .egg)
            let egg = eggText.flatMap(sheetEggStatus) ?? .unknown
            let audit = importRowAudit(
                rowNumber: headerRowIndex + rowOffset + 2,
                rocketName: rocketName,
                rocketWasMapped: value(in: columns, columnMap: columnMap, role: .rocket) != nil,
                mass: mass,
                massWasMapped: parsedMass != nil,
                altitude: altitude,
                altitudeSourceText: altitudeText,
                targetAltitude: targetAltitude,
                time: time,
                dateWasMapped: dateText.flatMap(sheetDate) != nil,
                weatherWasMapped: value(in: columns, columnMap: columnMap, role: .temperature) != nil ||
                    value(in: columns, columnMap: columnMap, role: .wind) != nil ||
                    value(in: columns, columnMap: columnMap, role: .humidity) != nil,
                eggWasMapped: eggText.flatMap(sheetEggStatus) != nil,
                importedPoints: importedPoints,
                notes: rowNotes
            )
            guard audit.shouldImport else { return nil }
            let enrichedNotes = [
                rowNotes,
                massText.map { _ in "Imported loaded mass: \(formattedGrams(mass))" },
                weatherConditions.map { "Weather conditions: \($0)" },
                recoveryBlanket.map { "Recovery blanket/wadding: \($0)" },
                importedPoints.map { "Imported sheet points: \($0)" },
                audit.noteText
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            let attachmentNames = value(in: columns, columnMap: columnMap, role: .attachments)?
                .components(separatedBy: " | ")
                .filter { !$0.isEmpty } ?? []
            let importSummary = importMappingSummary(headers: headers, columnMap: columnMap, fileName: fileName)
            let warnings = suspiciousImportWarnings(
                rocket: rocket,
                motor: motor,
                mass: mass,
                altitude: altitude,
                time: time,
                temperature: temp,
                wind: wind,
                humidity: humidity
            )
            let warningText = warnings.isEmpty ? "" : "Import warning: \(warnings.joined(separator: "; "))."
            let importedNotes = [enrichedNotes, warningText, importSummary].filter { !$0.isEmpty }.joined(separator: "\n")
            return Flight(
                rocketID: rocket.id,
                teamID: rocket.teamID,
                flownAt: date,
                motorType: MotorCatalog.motor(named: motor)?.motorClass ?? .other,
                motorDesignation: motor,
                rocketMassGrams: mass,
                weather: Weather(temperatureF: temp, windMPH: wind, humidityPercent: humidity, location: "Imported"),
                measuredAltitudeFeet: altitude,
                targetAltitudeFeet: targetAltitude,
                flightTimeSeconds: time,
                parachuteSizeInches: chute,
                parachuteReefedCentimeters: reefedCentimeters,
                descentSystem: "Imported",
                eggStatus: egg,
                notes: importedNotes,
                attachments: attachmentNames.map { FlightAttachment(fileName: $0) },
                round: store.flightMode.shortTitle
            )
        }
        return patternCheckedImportedFlights(parsedFlights)
    }

    private func patternCheckedImportedFlights(_ flights: [Flight]) -> [Flight] {
        guard flights.count >= 3 else {
            return flights.map { flight in
                appendedPatternNote(
                    to: flight,
                    note: "Sheet pattern check: passed row checks; not enough imported rows for same-weight pattern validation."
                )
            }
        }

        return flights.compactMap { flight in
            let sameMassNeighbors = flights.filter {
                $0.id != flight.id &&
                $0.motorDesignation == flight.motorDesignation &&
                abs($0.rocketMassGrams - flight.rocketMassGrams) <= 3
            }
            let sameHeightNeighbors = flights.filter {
                $0.id != flight.id &&
                $0.motorDesignation == flight.motorDesignation &&
                abs($0.measuredAltitudeFeet - flight.measuredAltitudeFeet) <= 15
            }
            var notes: [String] = []

            if !sameMassNeighbors.isEmpty {
                let expectedAltitude = median(sameMassNeighbors.map(\.measuredAltitudeFeet))
                let altitudeDelta = abs(flight.measuredAltitudeFeet - expectedAltitude)
                if altitudeDelta > max(90, expectedAltitude * 0.12) {
                    return nil
                }
                notes.append("Sheet pattern check: similar weight matched \(sameMassNeighbors.count) row(s), expected height about \(Int(expectedAltitude.rounded())) ft.")
            }

            if sameHeightNeighbors.count >= 2 {
                let expectedMass = median(sameHeightNeighbors.map(\.rocketMassGrams))
                let massDelta = abs(flight.rocketMassGrams - expectedMass)
                if massDelta > max(80, expectedMass * 0.14) {
                    return nil
                }
                notes.append("Sheet pattern check: similar height matched \(sameHeightNeighbors.count) row(s), expected weight about \(Int(expectedMass.rounded())) g.")
            }

            if notes.isEmpty, let trendNote = sheetTrendNote(for: flight, in: flights) {
                notes.append(trendNote)
            } else if notes.isEmpty {
                notes.append("Sheet pattern check: passed row checks; no close same-weight or same-height neighbor was available.")
            }

            return appendedPatternNote(to: flight, note: notes.joined(separator: "\n"))
        }
    }

    private func sheetTrendNote(for flight: Flight, in flights: [Flight]) -> String? {
        guard flights.count >= 6 else { return nil }
        let masses = flights.map(\.rocketMassGrams)
        let altitudes = flights.map(\.measuredAltitudeFeet)
        let averageMass = masses.reduce(0, +) / Double(masses.count)
        let averageAltitude = altitudes.reduce(0, +) / Double(altitudes.count)
        let variance = masses.reduce(0) { total, mass in
            let miss = mass - averageMass
            return total + miss * miss
        }
        guard variance > 0.1 else { return nil }

        let covariance = zip(masses, altitudes).reduce(0) { total, pair in
            total + (pair.0 - averageMass) * (pair.1 - averageAltitude)
        }
        let slope = covariance / variance
        let intercept = averageAltitude - slope * averageMass
        let expectedAltitude = slope * flight.rocketMassGrams + intercept
        let residuals = flights.map { abs($0.measuredAltitudeFeet - (slope * $0.rocketMassGrams + intercept)) }
        let typicalMiss = median(residuals)
        let miss = abs(flight.measuredAltitudeFeet - expectedAltitude)
        if miss > max(150, typicalMiss * 3.5) {
            return "Sheet pattern check: this row is unusual versus the weight-height trend, so review it after import."
        }
        return "Sheet pattern check: row is consistent with the sheet's weight-height trend."
    }

    private func appendedPatternNote(to flight: Flight, note: String) -> Flight {
        var checkedFlight = flight
        checkedFlight.notes = [checkedFlight.notes, note]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        return checkedFlight
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let midpoint = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[midpoint - 1] + sorted[midpoint]) / 2
        }
        return sorted[midpoint]
    }

    private enum SheetColumnRole: CaseIterable {
        case date
        case rocket
        case motor
        case mass
        case targetAltitude
        case altitude
        case time
        case temperature
        case wind
        case humidity
        case parachute
        case reefedCentimeters
        case weatherConditions
        case recoveryBlanket
        case importedPoints
        case egg
        case notes
        case attachments
    }

    private enum SheetUnit {
        case feet
        case meters
        case grams
        case kilograms
        case ounces
        case pounds
        case seconds
        case fahrenheit
        case celsius
        case mph
        case metersPerSecond
        case kilometersPerHour
        case percent
        case inches
        case centimeters
        case millimeters
    }

    private var altitudeKeys: [String] {
        ["altitude", "alt", "alt ft", "alt feet", "measured altitude", "measured alt", "altitude ft", "altitude feet", "actual altitude", "actual altitude ft", "flight altitude", "flight altitude ft", "apogee", "apogee ft", "apogee feet", "flight height", "flight height ft", "measured height", "max altitude", "peak altitude"]
    }

    private var targetAltitudeKeys: [String] {
        ["target altitude", "target alt", "target alt ft", "target altitude ft", "wanted altitude", "wanted alt", "wanted altitude ft", "goal altitude", "goal alt", "goal altitude ft", "planned altitude", "planned alt", "planned altitude ft"]
    }

    private var rocketKeys: [String] {
        ["rocket", "rocket name", "vehicle", "airframe", "rocket id"]
    }

    private var motorKeys: [String] {
        ["motor", "motor designation", "engine", "engine designation", "motor type"]
    }

    private var massKeys: [String] {
        ["mass", "mass g", "mass grams", "rocket mass", "rocket mass g", "loaded mass", "loaded mass g", "weight", "weight g", "wt", "wt g", "liftoff mass", "lift off mass"]
    }

    private var timeKeys: [String] {
        ["flight time", "flight time s", "flight time sec", "time", "duration", "duration s", "total time", "score time"]
    }

    private var temperatureKeys: [String] {
        ["temperature", "temperature f", "temp", "temp f", "air temp", "weather temp"]
    }

    private var windKeys: [String] {
        ["wind", "wind mph", "wind speed", "wind speed mph", "weather wind"]
    }

    private var humidityKeys: [String] {
        ["humidity", "humidity %", "relative humidity", "rh"]
    }

    private var parachuteKeys: [String] {
        ["parachute", "parachute in", "parachute size", "chute", "chute in", "chute size", "recovery"]
    }

    private var reefedCentimetersKeys: [String] {
        [
            "reef", "reefed", "reefed cm", "reef cm", "reefing", "reefing cm",
            "reef length", "reef length cm", "reefed length", "reefed length cm",
            "reefing length", "reefing length cm", "centimeters reefed", "cm reefed",
            "chute reef", "parachute reef", "recovery reef", "reef line",
            "reef cord", "reef string", "tie length", "tied length", "band length",
            "wrap length", "wrapped length", "chute opening", "opening cm"
        ]
    }

    private var notesKeys: [String] {
        ["notes", "comments", "comment", "observations"]
    }

    private var dateKeys: [String] {
        ["date", "flight date", "date time", "datetime", "time stamp", "timestamp", "launch date"]
    }

    private var eggKeys: [String] {
        ["egg", "egg status", "payload", "payload status", "egg condition"]
    }

    private var attachmentKeys: [String] {
        ["attachments", "attachment", "files", "file"]
    }

    private func roleKeys(_ role: SheetColumnRole) -> [String] {
        switch role {
        case .date: return dateKeys + ["launch time", "flight timestamp", "flown at"]
        case .rocket: return rocketKeys + ["rocket used", "vehicle name", "model"]
        case .motor: return motorKeys + ["engine code", "motor code", "designation", "reload"]
        case .mass: return massKeys + ["loaded weight", "launch weight", "gross weight", "total mass", "m liftoff"]
        case .targetAltitude: return targetAltitudeKeys + ["target height", "wanted height", "desired altitude", "desired height", "goal height"]
        case .altitude: return altitudeKeys + ["measured height", "achieved altitude", "observed altitude", "recorded altitude", "altimeter"]
        case .time: return timeKeys + ["duration sec", "flight duration", "official time", "score seconds", "seconds"]
        case .temperature: return temperatureKeys + ["degrees", "degrees f", "ambient temp", "outside temp"]
        case .wind: return windKeys + ["wind velocity", "breeze", "gust", "gust mph"]
        case .humidity: return humidityKeys + ["humid", "humidity percent"]
        case .parachute: return parachuteKeys + ["parachute diameter", "chute diameter", "recovery size"]
        case .reefedCentimeters: return reefedCentimetersKeys + ["reefed centimeters", "reef centimeters", "reefed amount", "reef amount", "tied cm", "band cm", "wrap cm", "opening centimeters"]
        case .weatherConditions: return ["weather conditions", "conditions", "sky", "clouds", "field weather"]
        case .recoveryBlanket: return ["dog barf", "dog barf g", "nomex", "wadding", "recovery blanket", "blanket"]
        case .importedPoints: return ["how many points", "points", "score", "flight score", "arc points"]
        case .egg: return eggKeys + ["egg result", "egg outcome", "payload result"]
        case .notes: return notesKeys + ["description", "remarks", "field notes"]
        case .attachments: return attachmentKeys + ["attachment names", "photo", "photos", "document"]
        }
    }

    private func inferredColumnMap(headers: [String], rows: [[String]]) -> [SheetColumnRole: Int] {
        var assignments: [SheetColumnRole: Int] = [:]
        var usedColumns = Set<Int>()
        let candidates = SheetColumnRole.allCases.flatMap { role in
            headers.enumerated().map { index, header in
                let score = columnScore(header, for: role) + columnDataScore(index: index, role: role, header: header, rows: rows)
                return (role: role, index: index, score: score)
            }
        }
        .filter { $0.score >= minimumColumnScore(for: $0.role) }
        .sorted {
            if $0.score == $1.score { return $0.index < $1.index }
            return $0.score > $1.score
        }

        for candidate in candidates {
            guard assignments[candidate.role] == nil, !usedColumns.contains(candidate.index) else { continue }
            assignments[candidate.role] = candidate.index
            usedColumns.insert(candidate.index)
        }
        return assignments
    }

    private func columnDataScore(index: Int, role: SheetColumnRole, header: String, rows: [[String]]) -> Double {
        let values = rows.prefix(80).compactMap { row -> String? in
            guard row.indices.contains(index) else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        guard !values.isEmpty else { return 0 }

        let sampled = values.prefix(40)
        let plausibleCount = sampled.filter { value in
            isPlausibleValue(value, role: role, header: header)
        }.count
        let ratio = Double(plausibleCount) / Double(sampled.count)
        let numericRoles: Set<SheetColumnRole> = [.altitude, .targetAltitude, .mass, .time, .temperature, .wind, .humidity, .parachute, .reefedCentimeters]
        let base = numericRoles.contains(role) ? 4.0 : 2.2
        return ratio * base
    }

    private func isPlausibleValue(_ value: String, role: SheetColumnRole, header: String) -> Bool {
        switch role {
        case .altitude, .targetAltitude, .mass, .time, .temperature, .wind, .humidity, .parachute:
            return plausibleSheetNumber(value, role: role, header: header, defaultUnit: defaultUnit(for: role)) != nil
        case .reefedCentimeters:
            return plausibleReefedCentimeters(value, header: header) != nil
        case .date:
            return sheetDate(value) != nil
        case .egg:
            return sheetEggStatus(value) != nil
        case .motor:
            return normalizedMotorDesignation(value).map {
                MotorCatalog.motor(named: $0) != nil ||
                    $0.range(of: #"[A-H][0-9]"#, options: .regularExpression) != nil
            } ?? false
        case .rocket, .weatherConditions, .recoveryBlanket, .importedPoints, .notes, .attachments:
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func defaultUnit(for role: SheetColumnRole) -> SheetUnit? {
        switch role {
        case .altitude, .targetAltitude: return .feet
        case .mass: return .grams
        case .time: return .seconds
        case .temperature: return .fahrenheit
        case .wind: return .mph
        case .humidity: return .percent
        case .parachute: return .inches
        case .reefedCentimeters: return .centimeters
        default: return nil
        }
    }

    private func columnScore(_ header: String, for role: SheetColumnRole) -> Double {
        let normalized = normalizedHeader(header)
        guard !normalized.isEmpty else { return 0 }
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        var best = 0.0
        for key in roleKeys(role).map(normalizedHeader) {
            let keyTokens = Set(key.split(separator: " ").map(String.init))
            guard !keyTokens.isEmpty else { continue }
            var score = 0.0
            if normalized == key {
                score += 8
            } else if normalized.contains(key) || key.contains(normalized) {
                score += 5
            }
            let overlap = tokens.intersection(keyTokens)
            score += Double(overlap.count) * 2.2
            score += unitScore(header, role: role)
            score -= rolePenalty(normalized, role: role)
            best = max(best, score)
        }
        return best
    }

    private func minimumColumnScore(for role: SheetColumnRole) -> Double {
        switch role {
        case .altitude, .targetAltitude, .mass:
            return 5.5
        default:
            return 4.5
        }
    }

    private func unitScore(_ header: String, role: SheetColumnRole) -> Double {
        let normalized = normalizedHeader(header)
        switch role {
        case .altitude, .targetAltitude:
            return normalized.contains("ft") || normalized.contains("feet") || normalized.contains("meter") || normalized.contains(" m") ? 1.2 : 0
        case .mass:
            return normalized.contains(" g") || normalized.contains("gram") || normalized.contains("kg") || normalized.contains("oz") || normalized.contains("lb") ? 1.2 : 0
        case .time:
            let tokens = Set(normalized.split(separator: " ").map(String.init))
            return tokens.contains("s") || normalized.contains("sec") || normalized.contains("second") ? 0.8 : 0
        case .temperature:
            return normalized.contains("f") || normalized.contains("c") || normalized.contains("temp") ? 0.8 : 0
        case .wind:
            return normalized.contains("mph") || normalized.contains("m s") || normalized.contains("km h") ? 0.8 : 0
        case .humidity:
            return normalized.contains("%") || normalized.contains("percent") ? 0.8 : 0
        case .parachute:
            return normalized.contains("in") || normalized.contains("inch") || normalized.contains("cm") ? 0.8 : 0
        case .reefedCentimeters:
            return normalized.contains("cm") || normalized.contains("centimeter") || normalized.contains("reef") ? 1.2 : 0
        default:
            return 0
        }
    }

    private func rolePenalty(_ normalizedHeader: String, role: SheetColumnRole) -> Double {
        switch role {
        case .altitude:
            let blocked = ["target", "wanted", "goal", "desired", "planned", "rocket height", "rocket length", "body length", "length", "diameter", "width", "span", "size", "point", "score"]
            return blocked.contains(where: { normalizedHeader.contains($0) }) ? 7 : 0
        case .targetAltitude:
            let blocked = ["measured", "actual", "observed", "recorded", "apogee", "max", "peak", "rocket height", "rocket length", "body length", "length", "diameter", "width", "point", "score"]
            return blocked.contains(where: { normalizedHeader.contains($0) }) ? 5 : 0
        case .time:
            return normalizedHeader.contains("date") || normalizedHeader.contains("timestamp") || normalizedHeader.contains("point") || normalizedHeader.contains("score") ? 5 : 0
        case .mass:
            return normalizedHeader.contains("motor mass") || normalizedHeader.contains("propellant") || normalizedHeader.contains("point") || normalizedHeader.contains("score") ? 4 : 0
        case .parachute:
            return normalizedHeader.contains("reef") ? 5 : 0
        case .reefedCentimeters:
            return normalizedHeader.contains("diameter") || normalizedHeader.contains("size") ? 4 : 0
        case .recoveryBlanket:
            return normalizedHeader.contains("weight") || normalizedHeader.contains("mass") ? 6 : 0
        case .wind:
            return normalizedHeader.contains("direction") ? 4 : 0
        default:
            return 0
        }
    }

    private func header(for role: SheetColumnRole, headers: [String], columnMap: [SheetColumnRole: Int]) -> String {
        guard let index = columnMap[role], headers.indices.contains(index) else { return "" }
        return headers[index]
    }

    private func importMappingSummary(headers: [String], columnMap: [SheetColumnRole: Int], fileName: String) -> String {
        let labels: [(SheetColumnRole, String)] = [
            (.altitude, "altitude"),
            (.targetAltitude, "target"),
            (.mass, "mass"),
            (.motor, "motor"),
            (.time, "time"),
            (.temperature, "temp"),
            (.wind, "wind"),
            (.humidity, "humidity"),
            (.parachute, "chute"),
            (.reefedCentimeters, "reef cm"),
            (.weatherConditions, "conditions"),
            (.recoveryBlanket, "recovery"),
            (.importedPoints, "points")
        ]
        let mapped = labels.compactMap { role, label -> String? in
            guard let index = columnMap[role], headers.indices.contains(index) else { return nil }
            return "\(label)=\(headers[index])"
        }
        guard !mapped.isEmpty else { return "Imported from \(fileName)." }
        return "Imported from \(fileName). Column map: \(mapped.joined(separator: ", "))."
    }

    private func suspiciousImportWarnings(
        rocket: Rocket,
        motor: String,
        mass: Double,
        altitude: Double,
        time: Double?,
        temperature: Double,
        wind: Double,
        humidity: Double
    ) -> [String] {
        var warnings: [String] = []
        if MotorCatalog.motor(named: motor) == nil {
            warnings.append("motor was not recognized")
        }
        if mass < rocket.dryMassGrams {
            warnings.append("loaded mass is below the rocket dry mass")
        }
        if altitude < 100 || altitude > importedAltitudeUpperBound {
            warnings.append("altitude is outside the usual ARC practice range")
        }
        if let time, !(5...180).contains(time) {
            warnings.append("flight time looks unusual")
        }
        if !(-20...130).contains(temperature) {
            warnings.append("temperature looks unusual")
        }
        if wind > 35 {
            warnings.append("wind looks unusually high")
        }
        if !(0...100).contains(humidity) {
            warnings.append("humidity is outside 0-100%")
        }
        return warnings
    }

    private struct ImportRowAudit {
        var shouldImport: Bool
        var noteText: String
    }

    private func importRowAudit(
        rowNumber: Int,
        rocketName: String,
        rocketWasMapped: Bool,
        mass: Double,
        massWasMapped: Bool,
        altitude: Double,
        altitudeSourceText: String,
        targetAltitude: Double?,
        time: Double?,
        dateWasMapped: Bool,
        weatherWasMapped: Bool,
        eggWasMapped: Bool,
        importedPoints: String?,
        notes: String
    ) -> ImportRowAudit {
        guard isReasonableImportedAltitude(altitude, targetAltitude: targetAltitude) else {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }
        guard (50...2_000).contains(mass) else {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }
        if let time, !(0...180).contains(time) {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }
        guard massWasMapped else {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }

        var confirmations = ["altitude"]
        if massWasMapped { confirmations.append("mass") }
        if rocketWasMapped || !rocketName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            confirmations.append("rocket")
        }
        if targetAltitude != nil { confirmations.append("target") }
        if let time, (5...120).contains(time) { confirmations.append("time") }
        if dateWasMapped { confirmations.append("date") }
        if weatherWasMapped { confirmations.append("weather") }
        if eggWasMapped { confirmations.append("egg") }

        let lowercasedNotes = notes.lowercased()
        let lowercasedAltitude = altitudeSourceText.lowercased()
        let brokenAltitudeMarkers = [
            "altimeter broke",
            "altimeter broken",
            "altimeter ??",
            "no altitude",
            "bad altitude",
            "lost altitude",
            "no data",
            "n/a",
            "broke",
            "broken",
            "invalid"
        ]
        if brokenAltitudeMarkers.contains(where: { lowercasedNotes.contains($0) || lowercasedAltitude.contains($0) }) {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }
        let uncertainAltitudeMarkers = ["??", "?", "smth", "something", "approx", "about", "around", "maybe"]
        if uncertainAltitudeMarkers.contains(where: { lowercasedAltitude.contains($0) }) {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }

        guard confirmations.count >= 3 else {
            return ImportRowAudit(shouldImport: false, noteText: "")
        }

        var reviewNotes = [
            "Import checked row \(rowNumber): \(confirmations.count) confirmations (\(confirmations.joined(separator: ", ")))."
        ]
        if let pointsWarning = importedPointsCrossCheck(
            importedPoints: importedPoints,
            altitude: altitude,
            targetAltitude: targetAltitude,
            time: time
        ) {
            reviewNotes.append(pointsWarning)
        }
        return ImportRowAudit(shouldImport: true, noteText: reviewNotes.joined(separator: "\n"))
    }

    private func importedPointsCrossCheck(
        importedPoints: String?,
        altitude: Double,
        targetAltitude: Double?,
        time: Double?
    ) -> String? {
        guard let importedPoints,
              let sheetPoints = firstSheetNumber(in: importedPoints.lowercased())
        else { return nil }

        let target = targetAltitude ?? store.targetAltitudeFeet
        var expectedPoints = abs(altitude - target)
        if let time {
            let range = store.syncedCompetitionInfo.flightTimeRange
            if time < range.lowerBound {
                expectedPoints += (range.lowerBound - time) * 4
            } else if time > range.upperBound {
                expectedPoints += (time - range.upperBound) * 4
            }
        }

        guard abs(expectedPoints - sheetPoints) > 40 else { return nil }
        return "Import review: sheet points were \(Int(sheetPoints.rounded())), app recalculated about \(Int(expectedPoints.rounded())) using the mapped altitude/time."
    }

    private func value(in columns: [String], columnMap: [SheetColumnRole: Int], role: SheetColumnRole) -> String? {
        guard let index = columnMap[role], columns.indices.contains(index) else { return nil }
        let value = columns[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isLikelyHeaderOrEmptyRow(_ columns: [String], headers: [String]) -> Bool {
        let filled = columns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !filled.isEmpty else { return true }
        let normalizedRow = filled.map(normalizedHeader)
        let normalizedHeaders = Set(headers.map(normalizedHeader))
        let headerMatches = normalizedRow.filter { normalizedHeaders.contains($0) }.count
        return headerMatches >= max(2, min(4, filled.count))
    }

    private func matchedRocket(named name: String) -> Rocket? {
        let normalizedName = normalizedHeader(name)
        return store.rockets.first { rocket in
            let candidate = normalizedHeader(rocket.name)
            return candidate == normalizedName || candidate.contains(normalizedName) || normalizedName.contains(candidate)
        }
    }

    private func normalizedMotorDesignation(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let match = trimmed.firstMatch(for: #"[A-H][0-9]{1,3}[A-Z]{0,3}(?:[-/][0-9]{1,2}(?:,[0-9]{1,2})?)?"#) {
            return match.uppercased()
        }
        return trimmed.uppercased()
    }

    private struct SheetText {
        var name: String
        var text: String
    }

    private func spreadsheetTexts(from data: Data, fileName: String) -> [SheetText] {
        let lowercasedName = fileName.lowercased()
        if lowercasedName.hasSuffix(".xlsx") {
            let worksheets = xlsxWorksheets(from: data)
            return worksheets.compactMap { worksheet in
                guard inferredHeaderRowIndex(in: worksheet.rows) != nil else { return nil }
                let text = worksheet.rows
                    .map { row in row.map(sheetEscape).joined(separator: "\t") }
                    .joined(separator: "\n")
                return SheetText(name: "\(fileName) • \(worksheet.name)", text: text)
            }
        }
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
            return [SheetText(name: fileName, text: text)]
        }
        return []
    }

    private func sheetEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func formattedGrams(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))g"
        }
        return "\(String(format: "%.1f", value))g"
    }

    private func detectedDelimiter(in lines: [String]) -> Character {
        let delimiters: [Character] = ["\t", ",", ";"]
        return delimiters.max { left, right in
            delimiterScore(left, lines: lines) < delimiterScore(right, lines: lines)
        } ?? "\t"
    }

    private func delimiterScore(_ delimiter: Character, lines: [String]) -> Int {
        lines.reduce(0) { total, line in
            total + parseDelimitedLine(line, delimiter: delimiter).count
        }
    }

    private func parseDelimitedLine(_ line: String, delimiter: Character) -> [String] {
        var output: [String] = []
        var current = ""
        var isQuoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    isQuoted.toggle()
                }
            } else if character == delimiter, !isQuoted {
                output.append(current)
                current = ""
            } else {
                current.append(character)
            }
            index = line.index(after: index)
        }
        output.append(current)
        return output.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func normalizedHeader(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func value(in columns: [String], indexByHeader: [String: Int], keys: [String]) -> String? {
        for key in keys.map(normalizedHeader) {
            if let index = indexByHeader[key], columns.indices.contains(index), !columns[index].isEmpty {
                return columns[index]
            }
        }

        for key in keys.map(normalizedHeader) {
            let keyTokens = Set(key.split(separator: " ").map(String.init))
            guard !keyTokens.isEmpty else { continue }
            let match = indexByHeader
                .filter { header, _ in
                    guard !header.isEmpty else { return false }
                    if key == "altitude",
                       ["target", "wanted", "goal", "planned"].contains(where: { header.contains($0) }) {
                        return false
                    }
                    let headerTokens = Set(header.split(separator: " ").map(String.init))
                    guard !headerTokens.isEmpty else { return false }
                    if header.contains(key) || key.contains(header) {
                        return true
                    }
                    let overlap = headerTokens.intersection(keyTokens)
                    return overlap.count >= min(2, keyTokens.count)
                }
                .sorted { $0.value < $1.value }
                .first

            if let index = match?.value, columns.indices.contains(index), !columns[index].isEmpty {
                return columns[index]
            }
        }
        return nil
    }

    private func inferredHeaderRowIndex(in rows: [[String]]) -> Int? {
        let fieldGroups = [
            altitudeKeys,
            rocketKeys,
            motorKeys,
            massKeys,
            timeKeys,
            temperatureKeys,
            windKeys,
            humidityKeys,
            parachuteKeys,
            reefedCentimetersKeys,
            dateKeys,
            eggKeys
        ]

        let candidates = rows.prefix(12).enumerated().map { index, row in
            let normalizedCells = row.map(normalizedHeader).filter { !$0.isEmpty }
            let score = fieldGroups.reduce(0) { total, keys in
                let matched = normalizedCells.contains { cell in
                    keys.map(normalizedHeader).contains { key in
                        cell == key || cell.contains(key) || key.contains(cell)
                    }
                }
                return total + (matched ? 1 : 0)
            }
            return (index, score)
        }

        return candidates.max { $0.1 < $1.1 }.flatMap { $0.1 >= 2 ? $0.0 : nil }
    }

    private func sheetNumber(_ value: String) -> Double? {
        sheetNumber(value, header: "", defaultUnit: nil)
    }

    private func sheetNumber(_ value: String, header: String, defaultUnit: SheetUnit?) -> Double? {
        let lowercased = value.lowercased()
        guard let number = firstSheetNumber(in: lowercased) else { return nil }
        let unit = inferredUnit(value: lowercased, header: header, defaultUnit: defaultUnit)
        return convertedSheetNumber(number, unit: unit)
    }

    private func plausibleSheetNumber(_ value: String, role: SheetColumnRole, header: String, defaultUnit: SheetUnit?) -> Double? {
        guard let number = sheetNumber(value, header: header, defaultUnit: defaultUnit) else { return nil }
        switch role {
        case .altitude, .targetAltitude:
            return (20...1_600).contains(number) ? number : nil
        case .mass:
            return (20...2_000).contains(number) ? number : nil
        case .time:
            return (0...300).contains(number) ? number : nil
        case .temperature:
            return (-40...140).contains(number) ? number : nil
        case .wind:
            return (0...120).contains(number) ? number : nil
        case .humidity:
            let percent = (0...1).contains(number) ? number * 100 : number
            return (0...100).contains(percent) ? percent : nil
        case .parachute:
            return (1...160).contains(number) ? number : nil
        case .reefedCentimeters:
            return (0...500).contains(number) ? number : nil
        default:
            return number
        }
    }

    private func isReasonableImportedAltitude(_ altitude: Double, targetAltitude: Double?) -> Bool {
        guard altitude.isFinite else { return false }
        guard (50...importedAltitudeUpperBound).contains(altitude) else { return false }
        if let targetAltitude, targetAltitude.isFinite, abs(altitude - targetAltitude) > 500 {
            return false
        }
        return true
    }

    private var importedAltitudeUpperBound: Double {
        let observedMax = store.flights
            .map(\.measuredAltitudeFeet)
            .filter { (100...1_600).contains($0) }
            .max()
        let reference = max(
            observedMax ?? 0,
            store.targetAltitudeFeet,
            store.syncedCompetitionInfo.altitudeGoalFeet
        )
        return min(1_600, max(1_000, reference + 300))
    }

    private func inferredTargetAltitude(from values: [String]) -> Double? {
        for value in values {
            let lowercased = value.lowercased()
            let matches = lowercased.matches(for: #"\b([5-9][0-9]{2})\s*(?:ft|feet|foot|')?\b"#)
            for match in matches {
                if let altitude = Double(match), (500...900).contains(altitude) {
                    return altitude
                }
            }
        }
        return nil
    }

    private func inferredReefedCentimeters(from values: [String], allowsBareCentimeterName: Bool = false) -> Double? {
        let combined = values.joined(separator: " ").lowercased()
        if combined.contains("no reef") ||
            combined.contains("unreefed") ||
            combined.contains("no wrap") ||
            combined.contains("0 reef") {
            return 0
        }

        let contextWords = [
            "reef", "reefed", "reefing", "chute", "parachute", "recovery",
            "shroud", "line", "cord", "string", "tie", "tied", "band",
            "wrap", "wrapped", "opening", "restrict", "restricted",
            "constrict", "loop"
        ]
        let hasReefingContext = contextWords.contains { combined.contains($0) }
        let cmValues = combined.matches(for: #"\b([0-9]+(?:\.[0-9]+)?)\s*(?:cm|centimeter|centimeters)\b"#)
            .compactMap(Double.init)
            .filter { (0...500).contains($0) }
        guard hasReefingContext || allowsBareCentimeterName else { return nil }

        let centimeterPatterns = [
            #"(?:reef|reefed|reefing|tie|tied|wrap|wrapped|band|line|cord|string|opening|restrict(?:ed|or)?|constrict(?:ed)?|loop)\s*(?:length|len|is|at|to|=|:|-)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:cm|centimeter|centimeters)"#,
            #"([0-9]+(?:\.[0-9]+)?)\s*(?:cm|centimeter|centimeters)\s*(?:reef|reefed|reefing|tie|tied|wrap|wrapped|band|line|cord|string|opening|restrict(?:ed|or)?|constrict(?:ed)?|loop)"#,
            #"reef(?:ed|ing)?\s*(?:a\s*)?(?:bit\s*)?([0-9]+(?:\.[0-9]+)?)\s*(?:cm|centimeter|centimeters)"#,
            #"reef(?:ed|ing)?\s*(?:length\s*)?(?:is|at|to|=|:)?\s*([0-9]+(?:\.[0-9]+)?)\b"#,
            #"\b(?:r|rf|reef)\s*[-_ ]?([0-9]+(?:\.[0-9]+)?)\b"#
        ]
        for pattern in centimeterPatterns {
            if let match = combined.firstMatch(for: pattern),
               let centimeters = Double(match),
               (0...500).contains(centimeters) {
                return centimeters
            }
        }

        let inchPatterns = [
            #"(?:reef|reefed|reefing|tie|tied|wrap|wrapped|band|opening)\s*(?:length|len|is|at|to|=|:|-)?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:in|inch|inches)"#,
            #"([0-9]+(?:\.[0-9]+)?)\s*(?:in|inch|inches)\s*(?:reef|reefed|reefing|tie|tied|wrap|wrapped|band|opening)"#
        ]
        for pattern in inchPatterns {
            if let match = combined.firstMatch(for: pattern),
               let inches = Double(match) {
                let centimeters = inches * 2.54
                if (0...500).contains(centimeters) {
                    return centimeters
                }
            }
        }

        if cmValues.count == 1 {
            return cmValues[0]
        }
        return nil
    }

    private func plausibleReefedCentimeters(_ value: String, header: String) -> Double? {
        let lowercased = value.lowercased()
        guard let rawNumber = firstSheetNumber(in: lowercased) else { return nil }
        let unit = inferredUnit(value: lowercased, header: header, defaultUnit: .centimeters)
        let centimeters: Double
        switch unit {
        case .inches:
            centimeters = rawNumber * 2.54
        case .millimeters:
            centimeters = rawNumber / 10
        case .meters:
            centimeters = rawNumber * 100
        default:
            centimeters = rawNumber
        }
        return (0...500).contains(centimeters) ? centimeters : nil
    }

    private func firstSheetNumber(in value: String) -> Double? {
        let cleaned = value.replacingOccurrences(of: ",", with: "")
        guard let range = cleaned.range(of: #"-?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(cleaned[range])
    }

    private func inferredUnit(value: String, header: String, defaultUnit: SheetUnit?) -> SheetUnit? {
        let combined = "\(normalizedHeader(header)) \(normalizedHeader(value))"
        if combined.contains("kg") || combined.contains("kilogram") { return .kilograms }
        if combined.contains("oz") || combined.contains("ounce") { return .ounces }
        if combined.contains("lb") || combined.contains("pound") { return .pounds }
        if combined.contains("gram") || combined.contains(" g") { return .grams }
        if combined.contains("meter") || combined.contains(" m ") { return .meters }
        if combined.contains("feet") || combined.contains("foot") || combined.contains(" ft") { return .feet }
        if combined.contains("cm") || combined.contains("centimeter") { return .centimeters }
        if combined.contains("mm") || combined.contains("millimeter") { return .millimeters }
        if combined.contains("inch") || combined.contains(" in") { return .inches }
        if combined.contains("celsius") || combined.contains(" deg c") || combined.contains(" c") { return .celsius }
        if combined.contains("fahrenheit") || combined.contains(" deg f") || combined.contains(" f") { return .fahrenheit }
        if combined.contains("m s") || combined.contains("m/s") { return .metersPerSecond }
        if combined.contains("km h") || combined.contains("km/h") || combined.contains("kph") { return .kilometersPerHour }
        if combined.contains("mph") { return .mph }
        if combined.contains("%") || combined.contains("percent") { return .percent }
        if combined.contains("sec") || combined.contains("second") || combined.hasSuffix(" s") { return .seconds }
        return defaultUnit
    }

    private func convertedSheetNumber(_ number: Double, unit: SheetUnit?) -> Double {
        switch unit {
        case .meters:
            return number * 3.28084
        case .kilograms:
            return number * 1_000
        case .ounces:
            return number * 28.3495
        case .pounds:
            return number * 453.592
        case .celsius:
            return number * 9 / 5 + 32
        case .metersPerSecond:
            return number * 2.23694
        case .kilometersPerHour:
            return number * 0.621371
        case .centimeters:
            return number / 2.54
        case .millimeters:
            return number / 25.4
        default:
            return number
        }
    }

    private func sheetDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let serial = Double(trimmed), serial > 10_000 {
            let wholeDays = floor(serial)
            let dayDate = Calendar.current.date(byAdding: .day, value: Int(wholeDays) - 25_569, to: Date(timeIntervalSince1970: 0))
            let fractionalSeconds = (serial - wholeDays) * 86_400
            return dayDate?.addingTimeInterval(fractionalSeconds)
        }
        let formats = [
            "M/d/yy, h:mm a",
            "M/d/yyyy, h:mm a",
            "M/d/yy h:mm a",
            "M/d/yyyy h:mm a",
            "M/d/yyyy",
            "M/d/yy",
            "MM-dd-yyyy",
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "MMM d, yyyy",
            "MMM d yyyy",
            "MMMM d, yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    private func sheetEggStatus(_ value: String) -> EggStatus? {
        let normalized = value.lowercased()
        if normalized.contains("not") || normalized.contains("none") || normalized.contains("no egg") { return .notCarried }
        if normalized.contains("intact") || normalized.contains("safe") || normalized.contains("ok") || normalized.contains("good") { return .intact }
        if normalized.contains("crack") { return .cracked }
        if normalized.contains("break") || normalized.contains("broken") { return .broken }
        return .unknown
    }

    private struct XLSXWorksheet {
        var name: String
        var rows: [[String]]
    }

    private func xlsxWorksheets(from data: Data) -> [XLSXWorksheet] {
        guard let archive = SimpleZIPArchive(data: data) else { return [] }
        let sharedStrings = archive.textFile(named: "xl/sharedStrings.xml").map(parseSharedStrings) ?? []
        return archive.fileNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted()
            .compactMap { sheetName -> XLSXWorksheet? in
                guard let sheetXML = archive.textFile(named: sheetName) else { return nil }
                let rows = parseWorksheetRows(sheetXML, sharedStrings: sharedStrings)
                guard !rows.isEmpty else { return nil }
                return XLSXWorksheet(name: sheetName.replacingOccurrences(of: "xl/worksheets/", with: ""), rows: rows)
            }
    }

    private func parseSharedStrings(_ xml: String) -> [String] {
        xml.matches(for: #"<si[\s\S]*?</si>"#).map { item in
            item.matches(for: #"<t[^>]*>([\s\S]*?)</t>"#)
                .map { $0.arcXMLText }
                .joined()
        }
    }

    private func parseWorksheetRows(_ xml: String, sharedStrings: [String]) -> [[String]] {
        xml.matches(for: #"<row[^>]*>[\s\S]*?</row>"#).map { rowXML in
            var row: [String] = []
            for cellXML in rowXML.matches(for: #"<c[^>]*>[\s\S]*?</c>"#) {
                let reference = cellXML.firstMatch(for: #"r="([A-Z]+)[0-9]+""#) ?? ""
                let columnIndex = spreadsheetColumnIndex(reference)
                while row.count <= columnIndex {
                    row.append("")
                }
                let type = cellXML.firstMatch(for: #"t="([^"]+)""#)
                let rawValue = cellXML.firstMatch(for: #"<v[^>]*>([\s\S]*?)</v>"#)
                    ?? cellXML.firstMatch(for: #"<t[^>]*>([\s\S]*?)</t>"#)
                    ?? ""
                if type == "s", let index = Int(rawValue), sharedStrings.indices.contains(index) {
                    row[columnIndex] = sharedStrings[index]
                } else {
                    row[columnIndex] = rawValue.arcXMLText
                }
            }
            return row
        }
        .filter { $0.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    private func spreadsheetColumnIndex(_ letters: String) -> Int {
        var result = 0
        for scalar in letters.unicodeScalars {
            guard scalar.value >= 65, scalar.value <= 90 else { continue }
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(result - 1, 0)
    }
}

private extension String {
    func matches(for pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap { match in
            let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
            guard let swiftRange = Range(range, in: self) else { return nil }
            return String(self[swiftRange])
        }
    }

    func firstMatch(for pattern: String) -> String? {
        matches(for: pattern).first
    }

    var arcXMLText: String {
        replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .arcPlainText
    }
}

private struct SimpleZIPArchive {
    struct Entry {
        var name: String
        var compressionMethod: UInt16
        var compressedSize: Int
        var uncompressedSize: Int
        var localHeaderOffset: Int
    }

    let data: Data
    let entries: [Entry]

    var fileNames: [String] {
        entries.map(\.name)
    }

    init?(data: Data) {
        self.data = data
        guard let centralDirectory = Self.centralDirectory(in: data) else { return nil }
        entries = Self.entries(in: data, centralDirectory: centralDirectory)
    }

    func textFile(named name: String) -> String? {
        guard
            let entry = entries.first(where: { $0.name == name }),
            let fileData = fileData(for: entry)
        else {
            return nil
        }
        return String(data: fileData, encoding: .utf8)
    }

    private func fileData(for entry: Entry) -> Data? {
        let offset = entry.localHeaderOffset
        guard data.uint32LE(at: offset) == 0x04034b50 else { return nil }
        let fileNameLength = Int(data.uint16LE(at: offset + 26))
        let extraLength = Int(data.uint16LE(at: offset + 28))
        let start = offset + 30 + fileNameLength + extraLength
        guard start >= 0, start + entry.compressedSize <= data.count else { return nil }
        let compressed = data.subdata(in: start..<(start + entry.compressedSize))
        if entry.compressionMethod == 0 {
            return compressed
        }
        if entry.compressionMethod == 8 {
            return compressed.inflated(expectedSize: entry.uncompressedSize)
        }
        return nil
    }

    private static func centralDirectory(in data: Data) -> (offset: Int, count: Int)? {
        guard data.count >= 22 else { return nil }
        let lowerBound = max(0, data.count - 65_536)
        for offset in stride(from: data.count - 22, through: lowerBound, by: -1) {
            if data.uint32LE(at: offset) == 0x06054b50 {
                let count = Int(data.uint16LE(at: offset + 10))
                let directoryOffset = Int(data.uint32LE(at: offset + 16))
                return (directoryOffset, count)
            }
        }
        return nil
    }

    private static func entries(in data: Data, centralDirectory: (offset: Int, count: Int)) -> [Entry] {
        var output: [Entry] = []
        var offset = centralDirectory.offset
        for _ in 0..<centralDirectory.count {
            guard offset + 46 <= data.count, data.uint32LE(at: offset) == 0x02014b50 else { break }
            let compressionMethod = data.uint16LE(at: offset + 10)
            let compressedSize = Int(data.uint32LE(at: offset + 20))
            let uncompressedSize = Int(data.uint32LE(at: offset + 24))
            let fileNameLength = Int(data.uint16LE(at: offset + 28))
            let extraLength = Int(data.uint16LE(at: offset + 30))
            let commentLength = Int(data.uint16LE(at: offset + 32))
            let localHeaderOffset = Int(data.uint32LE(at: offset + 42))
            let nameStart = offset + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }
            let name = String(data: data.subdata(in: nameStart..<nameEnd), encoding: .utf8) ?? ""
            output.append(
                Entry(
                    name: name,
                    compressionMethod: compressionMethod,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localHeaderOffset
                )
            )
            offset = nameEnd + extraLength + commentLength
        }
        return output
    }
}

private extension Data {
    func uint16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt8.self)
            return UInt16(pointer[offset]) | (UInt16(pointer[offset + 1]) << 8)
        }
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return withUnsafeBytes { bytes in
            let pointer = bytes.bindMemory(to: UInt8.self)
            return UInt32(pointer[offset])
                | (UInt32(pointer[offset + 1]) << 8)
                | (UInt32(pointer[offset + 2]) << 16)
                | (UInt32(pointer[offset + 3]) << 24)
        }
    }

    func inflated(expectedSize: Int) -> Data? {
        guard expectedSize > 0 else { return nil }
        return withUnsafeBytes { sourceBuffer in
            guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            var output = Data(count: expectedSize)
            let decodedCount = output.withUnsafeMutableBytes { destinationBuffer in
                guard let destination = destinationBuffer.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destination,
                    expectedSize,
                    source,
                    count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
            guard decodedCount > 0 else { return nil }
            output.removeSubrange(decodedCount..<output.count)
            return output
        }
    }
}

private struct FlightSheetDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.tabSeparatedText, .plainText, .json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct FlightSheetPicker: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var onComplete: (Result<[URL], Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onComplete: (Result<[URL], Error>) -> Void

        init(onComplete: @escaping (Result<[URL], Error>) -> Void) {
            self.onComplete = onComplete
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onComplete(.success(urls))
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onComplete(.success([]))
        }
    }
}
