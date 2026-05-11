import SwiftUI
import PhotosUI

struct QuickLogView: View {
    @EnvironmentObject private var store: FlightStore
    @StateObject private var deviceLocation = DeviceLocationService()
    @State private var selectedRocketID: UUID?
    @State private var selectedMotorDesignation = "F24W-4,7"
    @State private var mass: Double?
    @State private var wantedAltitude: Double?
    @State private var altitude: Double?
    @State private var temperature: Double?
    @State private var wind: Double?
    @State private var humidity: Double?
    @State private var flightTimeSeconds: Double?
    @State private var location = "Manassas, VA"
    @State private var parachute: Double?
    @State private var reefedCentimeters: Double?
    @State private var descentSystem = "Reefed chute"
    @State private var eggStatus: EggStatus = .intact
    @State private var notes = ""
    @State private var attachments: [FlightAttachment] = []
    @State private var weatherStatus = "Manual values work offline."
    @State private var isLoadingWeather = false
    @State private var editingFlightID: UUID?
    @State private var expandedFlightID: UUID?
    @State private var isFieldMode = false
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var videoAttachmentStatus: String?
    @State private var analyzingVideoAttachmentID: UUID?
    @State private var showSaveConfirmation = false
    @State private var saveConfirmationText = "Flight saved"
    @State private var saveConfirmationToken = UUID()
    @State private var visibleFlightLimit = 35

    private let flightPageSize = 35

    private var selectedRocket: Rocket? {
        if let selectedRocketID,
           let rocket = store.rockets.first(where: { $0.id == selectedRocketID }) {
            return rocket
        }
        return store.rockets.first
    }

    private var availableMotors: [MotorSpec] {
        MotorCatalog.motors(for: store.flightMode)
    }

    private var displayedFlights: [Flight] {
        Array(store.flights.prefix(visibleFlightLimit))
    }

    private var hasMoreLoggedFlights: Bool {
        visibleFlightLimit < store.flights.count
    }

    private var canSaveFlight: Bool {
        selectedRocket != nil &&
        mass != nil &&
        altitude != nil &&
        parachute != nil &&
        (!store.isNationalsMode || wantedAltitude != nil) &&
        (!store.isCompetitionMode || flightTimeSeconds != nil)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 16) {
                        fieldModeToggle
                        weatherCard
                        if showSaveConfirmation {
                            saveConfirmationBanner
                                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                        }
                        if editingFlightID == nil {
                            if isFieldMode {
                                fieldLogForm
                            } else {
                                logForm
                            }
                        }
                        loggedFlightsCard
                    }
                    .padding()
                    .padding(.bottom, 28)
                }
                .onChange(of: editingFlightID) { _, flightID in
                    guard let flightID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            scrollProxy.scrollTo("flight-row-\(flightID.uuidString)", anchor: .center)
                        }
                    }
                }
            }
            .background {
                ARCBackground()
                    .allowsHitTesting(false)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.visible)
            .navigationTitle("\(store.flightMode.shortTitle) Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                primeDefaultValues()
            }
            .onChange(of: store.flightMode) { _, _ in
                normalizeLogSelections()
                applySelectedRocketDefaults()
            }
            .onChange(of: store.rockets) { _, _ in
                normalizeLogSelections()
                applySelectedRocketDefaults()
            }
            .onChange(of: selectedRocketID) { _, _ in
                applySelectedRocketDefaults()
            }
            .onChange(of: selectedVideoItem) { _, item in
                guard let item else { return }
                Task { await attachVideoFromGallery(item) }
            }
        }
    }

    private var fieldModeToggle: some View {
        Toggle(isOn: $isFieldMode) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Field Mode")
                    .font(.headline)
                Text("Bigger controls for fast logging at a launch site.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .cardStyle()
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live Weather", systemImage: "cloud.sun.fill")
                .font(.headline)
            Text("Launch site: \(location)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                Task { await pullWeatherFromPhoneLocation() }
            } label: {
                if isLoadingWeather {
                    ProgressView()
                } else {
                    Label("Use iPhone Location", systemImage: "location.fill")
                }
            }
            .buttonStyle(.bordered)
            Text(weatherStatus)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var saveConfirmationBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.arcMint)
                .symbolEffect(.bounce, value: showSaveConfirmation)
            VStack(alignment: .leading, spacing: 2) {
                Text(saveConfirmationText)
                    .font(.headline)
                Text("Your logbook and Insights data were updated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.arcMint.opacity(0.45)))
    }

    private var logForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Flight Entry", systemImage: "paperplane.fill")
                    .font(.headline)
                Text(entryModeDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Picker("Rocket", selection: $selectedRocketID) {
                ForEach(store.rockets) { rocket in
                    Text(rocket.name).tag(Optional(rocket.id))
                }
            }
            .pickerStyle(.menu)

            MotorSelectionField(selection: $selectedMotorDesignation, motors: availableMotors)

            VStack(alignment: .leading, spacing: 8) {
                Label("Egg Payload", systemImage: "oval.fill")
                    .font(.headline)
                Text("Record the condition of the egg after the flight.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(EggStatus.allCases) { status in
                    Button {
                        eggStatus = status
                    } label: {
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(eggStatus == status ? .black : .primary)
                    .background(eggStatus == status ? Color.arcMint : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(eggStatus == status ? Color.arcMint : .white.opacity(0.14)))
                }
            }

            OptionalNumberField(title: "Rocket Mass", value: $mass, suffix: "g")
            if store.isNationalsMode {
                OptionalNumberField(title: "Wanted Altitude", value: $wantedAltitude, suffix: "ft")
            }
            OptionalNumberField(title: "Measured Altitude", value: $altitude, suffix: "ft")
            if store.isCompetitionMode {
                OptionalNumberField(title: "Flight Time", value: $flightTimeSeconds, suffix: "s")
            }

            HStack {
                OptionalNumberField(title: "Temp", value: $temperature, suffix: "F")
                OptionalNumberField(title: "Wind", value: $wind, suffix: "mph")
            }

            HStack {
                OptionalNumberField(title: "Humidity", value: $humidity, suffix: "%")
                OptionalNumberField(title: "Chute", value: $parachute, suffix: "in")
            }
            OptionalNumberField(title: "Reefed Length", value: $reefedCentimeters, suffix: "cm")

            TextField("Descent system", text: $descentSystem)
                .fieldStyle()
            TextField("Notes", text: $notes, axis: .vertical)
                .fieldStyle()
            attachmentPicker

            Button {
                saveFlight()
            } label: {
                Label("Save Flight", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSaveFlight)
        }
        .cardStyle()
    }

    private var fieldLogForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Quick Flight", systemImage: "bolt.fill")
                .font(.title3.bold())

            Picker("Rocket", selection: $selectedRocketID) {
                ForEach(store.rockets) { rocket in
                    Text(rocket.name).tag(Optional(rocket.id))
                }
            }
            .pickerStyle(.menu)

            MotorSelectionField(selection: $selectedMotorDesignation, motors: availableMotors)

            if store.isNationalsMode {
                OptionalNumberField(title: "Wanted Altitude", value: $wantedAltitude, suffix: "ft")
            }
            OptionalNumberField(title: "Measured Altitude", value: $altitude, suffix: "ft")
            OptionalNumberField(title: "Loaded Mass", value: $mass, suffix: "g")
            if store.isCompetitionMode {
                OptionalNumberField(title: "Flight Time", value: $flightTimeSeconds, suffix: "s")
            }
            HStack {
                OptionalNumberField(title: "Wind", value: $wind, suffix: "mph")
                OptionalNumberField(title: "Chute", value: $parachute, suffix: "in")
            }
            OptionalNumberField(title: "Reefed Length", value: $reefedCentimeters, suffix: "cm")
            attachmentPicker
            Button {
                saveFlight()
            } label: {
                Label("Log Flight Now", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSaveFlight)
        }
        .cardStyle()
    }

    private var attachmentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                Label("Attach Launch Video", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let videoAttachmentStatus {
                Text(videoAttachmentStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(attachments) { attachment in
                attachmentRow(attachment)
            }
        }
    }

    private func attachmentRow(_ attachment: FlightAttachment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: attachment.kind == .video ? "video.fill" : "doc.fill")
                    .foregroundStyle(attachment.kind == .video ? Color.arcMint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(attachment.kind == .video ? "Launch video" : "Attached file")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if attachment.kind == .video {
                    Button {
                        Task { await analyzeVideoAttachment(attachment) }
                    } label: {
                        if analyzingVideoAttachmentID == attachment.id {
                            ProgressView()
                        } else {
                            Text("Analyze")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(analyzingVideoAttachmentID != nil)
                }
                Button(role: .destructive) {
                    VideoFlightAnalyzer.deleteStoredVideo(for: attachment)
                    attachments.removeAll { $0.id == attachment.id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            if let analysisSummary = attachment.analysisSummary, !analysisSummary.isEmpty {
                Text(analysisSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private var loggedFlightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Manage Flights")
                .font(.title3.bold())
            if store.flights.isEmpty {
                Text("No flights logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Showing \(displayedFlights.count) of \(store.flights.count) logged flights. Spreadsheet imports can be edited or deleted here too.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                let previousFlights = previousFlightLookup(for: displayedFlights)
                let rocketNamesByID = Dictionary(uniqueKeysWithValues: store.rockets.map { ($0.id, $0.name) })
                LazyVStack(spacing: 10) {
                    ForEach(displayedFlights) { flight in
                        let summary = store.scoreSummary(for: flight)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(rocketNamesByID[flight.rocketID] ?? "Unknown Rocket")
                                        .font(.headline)
                                    if editingFlightID == flight.id {
                                        Text("Editing")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.arcMint)
                                    }
                                    Text("\(Int(flight.measuredAltitudeFeet)) ft • \(flight.motorDesignation) • \(formattedGrams(flight.rocketMassGrams))")
                                        .foregroundStyle(.secondary)
                                    if (flight.round ?? "") == FlightMode.nationals.shortTitle {
                                        Text("Target: \(Int(store.scoringTargetAltitude(for: flight))) ft")
                                            .font(.caption)
                                            .foregroundStyle(Color.arcAmber)
                                    }
                                    if let flightTimeSeconds = flight.flightTimeSeconds {
                                        Text("\(String(format: "%.1f", flightTimeSeconds)) s")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("Egg: \(flight.eggStatus.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    qualityBadge(for: flight)
                                    if let comparison = comparisonText(for: flight, previous: previousFlights[flight.id]) {
                                        Text(comparison)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !flight.attachments.isEmpty {
                                        Text(attachmentSummary(for: flight))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let reefedCentimeters = flight.parachuteReefedCentimeters {
                                        Text("Reefed: \(String(format: "%.1f", reefedCentimeters)) cm")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    flightScoreBadge(for: flight, summary: summary)
                                    if summary.isDisqualified {
                                        Text("Disqualified: \(summary.disqualificationReasons.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundStyle(Color.arcOrange)
                                    }
                                    if expandedFlightID != flight.id,
                                       flight.attachments.contains(where: { $0.kind == .video }) {
                                        Text("Video analysis is saved for this flight and still feeds the AI model.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    flightDropdownButton(
                                        title: "Summary",
                                        isExpanded: expandedFlightID == flight.id
                                    ) {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                            expandedFlightID = expandedFlightID == flight.id ? nil : flight.id
                                        }
                                    }
                                    flightDropdownButton(
                                        title: "Edit",
                                        isExpanded: editingFlightID == flight.id
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                                            if editingFlightID == flight.id {
                                                editingFlightID = nil
                                            } else {
                                                editingFlightID = flight.id
                                                expandedFlightID = nil
                                            }
                                        }
                                    }
                                    Button("Delete", role: .destructive) {
                                        if editingFlightID == flight.id {
                                            editingFlightID = nil
                                        }
                                        flight.attachments.forEach(VideoFlightAnalyzer.deleteStoredVideo)
                                        store.deleteFlight(id: flight.id)
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            if expandedFlightID == flight.id {
                                flightIssueAnalysisCard(for: flight)
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            if editingFlightID == flight.id {
                                QuickFlightInlineEditor(flight: flight) {
                                    editingFlightID = nil
                                    showSavedConfirmation("Flight updated")
                                } onCancel: {
                                    editingFlightID = nil
                                }
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            Text(flight.flownAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("flight-row-\(flight.id.uuidString)")
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard editingFlightID != flight.id else { return }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                expandedFlightID = expandedFlightID == flight.id ? nil : flight.id
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
                    }
                }
                if hasMoreLoggedFlights {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                            visibleFlightLimit = min(visibleFlightLimit + flightPageSize, store.flights.count)
                        }
                    } label: {
                        Label("Show \(min(flightPageSize, store.flights.count - visibleFlightLimit)) More Flights", systemImage: "chevron.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .cardStyle()
    }

    private func pullWeatherFromPhoneLocation() async {
        isLoadingWeather = true
        weatherStatus = "Finding iPhone location..."
        do {
            let site = try await deviceLocation.currentLaunchSite()
            weatherStatus = "Fetching weather..."
            let weather = try await WeatherService.lookup(
                latitude: site.latitude,
                longitude: site.longitude,
                label: site.label
            )
            temperature = weather.temperatureF.rounded()
            wind = weather.windMPH.rounded()
            humidity = weather.humidityPercent.rounded()
            location = weather.location
            weatherStatus = "Loaded weather for \(weather.location)"
        } catch {
            weatherStatus = error.localizedDescription
        }
        isLoadingWeather = false
    }

    private func saveFlight() {
        guard let rocket = selectedRocket,
              let mass,
              let altitude,
              let parachute else {
            return
        }
        store.addFlight(
            rocket: rocket,
            motorDesignation: selectedMotorDesignation,
            mass: mass,
            weather: Weather(temperatureF: temperature ?? 0, windMPH: wind ?? 0, humidityPercent: humidity ?? 0, location: location),
            altitude: altitude,
            targetAltitude: store.isNationalsMode ? wantedAltitude : nil,
            flightTimeSeconds: store.isCompetitionMode ? flightTimeSeconds : nil,
            parachute: parachute,
            reefedCentimeters: reefedCentimeters,
            descentSystem: descentSystem,
            eggStatus: eggStatus,
            notes: notes,
            attachments: attachments
        )
        resetForm()
        showSavedConfirmation("Flight added")
    }

    private func flightDropdownButton(title: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isExpanded ? "Hide \(title)" : title)
                .frame(minWidth: 76)
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isExpanded)
        }
        .buttonStyle(.bordered)
    }

    private func showSavedConfirmation(_ text: String) {
        let token = UUID()
        saveConfirmationToken = token
        saveConfirmationText = text
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            showSaveConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
            guard saveConfirmationToken == token else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                showSaveConfirmation = false
            }
        }
    }

    @MainActor
    private func attachVideoFromGallery(_ item: PhotosPickerItem) async {
        videoAttachmentStatus = "Loading video from Photos..."
        defer { selectedVideoItem = nil }

        do {
            guard let pickedVideo = try await item.loadTransferable(type: PickedFlightVideo.self) else {
                videoAttachmentStatus = "Could not load that video. Try another clip."
                return
            }
            attachments.append(pickedVideo.attachment)
            videoAttachmentStatus = "Attached \(pickedVideo.attachment.fileName). You can analyze it before saving."
        } catch {
            videoAttachmentStatus = error.localizedDescription
        }
    }

    @MainActor
    private func analyzeVideoAttachment(_ attachment: FlightAttachment) async {
        analyzingVideoAttachmentID = attachment.id
        defer { analyzingVideoAttachmentID = nil }

        do {
            let result = try await Task.detached(priority: .utility) {
                try await VideoFlightAnalyzer.analyze(attachment)
            }.value
            guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
            attachments[index].analysisSummary = result.summary
            attachments[index].videoEstimatedFlightTimeSeconds = result.durationSeconds.isFinite ? result.durationSeconds : nil
            attachments[index].videoModelConfidence = result.modelConfidence
            if flightTimeSeconds == nil, result.modelConfidence >= 0.55 {
                flightTimeSeconds = result.durationSeconds.rounded()
            }
        } catch {
            videoAttachmentStatus = error.localizedDescription
        }
    }

    private func attachmentSummary(for flight: Flight) -> String {
        let videoCount = flight.attachments.filter { $0.kind == .video }.count
        let fileCount = flight.attachments.count - videoCount
        if videoCount > 0 && fileCount > 0 {
            return "\(videoCount) video\(videoCount == 1 ? "" : "s") • \(fileCount) file\(fileCount == 1 ? "" : "s")"
        }
        if videoCount > 0 {
            return "\(videoCount) launch video\(videoCount == 1 ? "" : "s")"
        }
        return "\(fileCount) file\(fileCount == 1 ? "" : "s")"
    }

    private func flightIssueAnalysisCard(for flight: Flight) -> some View {
        let analysis = VideoFlightAnalyzer.diagnoseFlight(
            flight: flight,
            rocket: store.rocket(for: flight),
            targetAltitudeFeet: diagnosisTargetAltitude(for: flight),
            targetFlightTimeRange: diagnosisTimeRange(for: flight)
        )
        return VStack(alignment: .leading, spacing: 6) {
            Label(analysis.title, systemImage: "waveform.and.magnifyingglass")
                .font(.caption.weight(.bold))
                .foregroundStyle(analysisColor(analysis.severityColorName))
            Text(analysis.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(analysis.evidence.prefix(3), id: \.self) { item in
                Text("Evidence: \(item)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(analysis.recommendations.prefix(2), id: \.self) { item in
                Text("Try: \(item)")
                    .font(.caption2)
                    .foregroundStyle(Color.arcMint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(analysisColor(analysis.severityColorName).opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(analysisColor(analysis.severityColorName).opacity(0.35))
        )
    }

    private func analysisColor(_ name: String) -> Color {
        switch name {
        case "mint":
            return Color.arcMint
        case "orange":
            return Color.arcOrange
        default:
            return Color.arcAmber
        }
    }

    private func diagnosisTargetAltitude(for flight: Flight) -> Double {
        if (flight.round ?? "") == FlightMode.hobby.shortTitle {
            return flight.targetAltitudeFeet ?? store.targetAltitudeFeet
        }
        return store.scoringTargetAltitude(for: flight)
    }

    private func diagnosisTimeRange(for flight: Flight) -> ClosedRange<Double>? {
        (flight.round ?? "") == FlightMode.hobby.shortTitle ? nil : store.syncedCompetitionInfo.flightTimeRange
    }

    @ViewBuilder
    private func qualityBadge(for flight: Flight) -> some View {
        let quality = dataQuality(for: flight)
        Text("Data quality: \(quality.label)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(quality.color)
    }

    private func dataQuality(for flight: Flight) -> (label: String, color: Color) {
        var score = 0
        if flight.rocketMassGrams.isFinite { score += 1 }
        if flight.measuredAltitudeFeet.isFinite { score += 1 }
        if flight.weather.temperatureF != 0 || flight.weather.windMPH != 0 || flight.weather.humidityPercent != 0 { score += 1 }
        if flight.flightTimeSeconds != nil { score += 1 }
        if flight.attachments.contains(where: { ($0.videoModelConfidence ?? 0) >= 0.55 }) { score += 1 }
        if score >= 4 { return ("Strong", Color.arcMint) }
        if score >= 3 { return ("Okay", Color.arcAmber) }
        return ("Needs more info", Color.arcOrange)
    }

    private func previousFlightLookup(for flights: [Flight]) -> [UUID: Flight] {
        var previousByFlightID: [UUID: Flight] = [:]
        var latestByRocketID: [UUID: Flight] = [:]
        for flight in flights.sorted(by: { $0.flownAt < $1.flownAt }) {
            previousByFlightID[flight.id] = latestByRocketID[flight.rocketID]
            latestByRocketID[flight.rocketID] = flight
        }
        return previousByFlightID
    }

    private func comparisonText(for flight: Flight, previous: Flight?) -> String? {
        guard let previous else {
            return nil
        }
        let altitudeDelta = flight.measuredAltitudeFeet - previous.measuredAltitudeFeet
        let massDelta = flight.rocketMassGrams - previous.rocketMassGrams
        let motorText = flight.motorDesignation == previous.motorDesignation ? "same motor" : "\(previous.motorDesignation) to \(flight.motorDesignation)"
        let windDelta = flight.weather.windMPH - previous.weather.windMPH
        return "Vs previous: \(signedInt(altitudeDelta)) ft, \(signedInt(massDelta)) g, \(motorText), \(signedInt(windDelta)) mph wind."
    }

    private func signedInt(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded >= 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func formattedGrams(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))g"
        }
        return "\(String(format: "%.1f", value))g"
    }

    private func primeDefaultValues() {
        normalizeLogSelections()
        applySelectedRocketDefaults()
    }

    private func applySelectedRocketDefaults() {
        guard editingFlightID == nil, let rocket = selectedRocket else { return }
        selectedMotorDesignation = rocket.defaultMotorDesignation
        if descentSystem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || descentSystem == "Reefed chute" {
            descentSystem = "Chute \(Int(rocket.parachuteSizeInches)) in"
        }
    }

    private func normalizeLogSelections() {
        if let selectedRocketID,
           !store.rockets.contains(where: { $0.id == selectedRocketID }) {
            self.selectedRocketID = store.rockets.first?.id
        } else {
            selectedRocketID = selectedRocketID ?? store.rockets.first?.id
        }

        if !availableMotors.contains(where: { $0.designation == selectedMotorDesignation }) {
            selectedMotorDesignation = selectedRocket?.defaultMotorDesignation ?? availableMotors.first?.designation ?? selectedMotorDesignation
        }
        if !availableMotors.contains(where: { $0.designation == selectedMotorDesignation }),
           let firstMotor = availableMotors.first {
            selectedMotorDesignation = firstMotor.designation
        }
    }

    private func resetForm() {
        editingFlightID = nil
        eggStatus = .intact
        notes = ""
        attachments = []
        videoAttachmentStatus = nil
        descentSystem = "Reefed chute"
        mass = nil
        wantedAltitude = nil
        altitude = nil
        temperature = nil
        wind = nil
        humidity = nil
        flightTimeSeconds = nil
        parachute = nil
        reefedCentimeters = nil
        primeDefaultValues()
    }

    @ViewBuilder
    private func flightScoreBadge(for flight: Flight, summary: FlightScoreSummary) -> some View {
        if store.isCompetitionMode || (flight.round ?? "") != FlightMode.hobby.shortTitle {
            if summary.isDisqualified {
                Text("Disqualified")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.arcOrange)
            } else if let totalPoints = summary.totalPoints {
                Text("\(totalPoints) points • \(summary.altitudePoints) altitude • \(summary.timePoints) time")
                    .font(.caption)
                    .foregroundStyle(Color.arcMint)
            }
        }
    }

    private var entryModeDescription: String {
        switch store.flightMode {
        case .hobby:
            return "Use this mode for casual flights, experiments, and non-targeted testing."
        case .competition:
            return "Use this mode for target-altitude practice and quick scoring comparisons."
        case .nationals:
            return "Use this mode for official launch-day logging with locked rocket configurations."
        }
    }
}

private struct QuickFlightInlineEditor: View {
    @EnvironmentObject private var store: FlightStore

    let flight: Flight
    let onSaved: () -> Void
    let onCancel: () -> Void
    private let originalAttachmentIDs: Set<UUID>

    @State private var selectedRocketID: UUID?
    @State private var selectedMotorDesignation: String
    @State private var mass: Double?
    @State private var wantedAltitude: Double?
    @State private var altitude: Double?
    @State private var temperature: Double?
    @State private var wind: Double?
    @State private var humidity: Double?
    @State private var flightTimeSeconds: Double?
    @State private var location: String
    @State private var parachute: Double?
    @State private var reefedCentimeters: Double?
    @State private var descentSystem: String
    @State private var eggStatus: EggStatus
    @State private var notes: String
    @State private var attachments: [FlightAttachment]
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var videoAttachmentStatus: String?
    @State private var analyzingVideoAttachmentID: UUID?

    init(flight: Flight, onSaved: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.flight = flight
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.originalAttachmentIDs = Set(flight.attachments.map(\.id))
        _selectedRocketID = State(initialValue: flight.rocketID)
        _selectedMotorDesignation = State(initialValue: flight.motorDesignation)
        _mass = State(initialValue: flight.rocketMassGrams)
        _wantedAltitude = State(initialValue: flight.targetAltitudeFeet)
        _altitude = State(initialValue: flight.measuredAltitudeFeet)
        _temperature = State(initialValue: flight.weather.temperatureF)
        _wind = State(initialValue: flight.weather.windMPH)
        _humidity = State(initialValue: flight.weather.humidityPercent)
        _flightTimeSeconds = State(initialValue: flight.flightTimeSeconds)
        _location = State(initialValue: flight.weather.location)
        _parachute = State(initialValue: flight.parachuteSizeInches)
        _reefedCentimeters = State(initialValue: flight.parachuteReefedCentimeters)
        _descentSystem = State(initialValue: flight.descentSystem)
        _eggStatus = State(initialValue: flight.eggStatus)
        _notes = State(initialValue: FlightNoteCleaner.editableNotes(from: flight.notes))
        _attachments = State(initialValue: flight.attachments)
    }

    private var selectedRocket: Rocket? {
        if let selectedRocketID,
           let rocket = store.rockets.first(where: { $0.id == selectedRocketID }) {
            return rocket
        }
        return store.rockets.first
    }

    private var availableMotors: [MotorSpec] {
        MotorCatalog.motors(for: store.flightMode)
    }

    private var canSave: Bool {
        selectedRocket != nil &&
        mass != nil &&
        altitude != nil &&
        parachute != nil &&
        (!store.isNationalsMode || wantedAltitude != nil) &&
        (!store.isCompetitionMode || flightTimeSeconds != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Edit this flight", systemImage: "square.and.pencil")
                .font(.headline)

            Picker("Rocket", selection: $selectedRocketID) {
                ForEach(store.rockets) { rocket in
                    Text(rocket.name).tag(Optional(rocket.id))
                }
            }
            .pickerStyle(.menu)

            MotorSelectionField(selection: $selectedMotorDesignation, motors: availableMotors)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(EggStatus.allCases) { status in
                    Button {
                        eggStatus = status
                    } label: {
                        Text(status.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(eggStatus == status ? .black : .primary)
                    .background(eggStatus == status ? Color.arcMint : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(eggStatus == status ? Color.arcMint : .white.opacity(0.14)))
                }
            }

            OptionalNumberField(title: "Rocket Mass", value: $mass, suffix: "g")
            if store.isNationalsMode {
                OptionalNumberField(title: "Wanted Altitude", value: $wantedAltitude, suffix: "ft")
            }
            OptionalNumberField(title: "Measured Altitude", value: $altitude, suffix: "ft")
            if store.isCompetitionMode {
                OptionalNumberField(title: "Flight Time", value: $flightTimeSeconds, suffix: "s")
            }
            HStack {
                OptionalNumberField(title: "Temp", value: $temperature, suffix: "F")
                OptionalNumberField(title: "Wind", value: $wind, suffix: "mph")
            }
            HStack {
                OptionalNumberField(title: "Humidity", value: $humidity, suffix: "%")
                OptionalNumberField(title: "Chute", value: $parachute, suffix: "in")
            }
            OptionalNumberField(title: "Reefed Length", value: $reefedCentimeters, suffix: "cm")
            TextField("Descent system", text: $descentSystem)
                .fieldStyle()
            TextField("Notes", text: $notes, axis: .vertical)
                .fieldStyle()
            attachmentPicker

            HStack {
                Button {
                    save()
                } label: {
                    Label("Update Flight", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)

                Button("Cancel") {
                    cancel()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.arcMint.opacity(0.28)))
        .onChange(of: selectedVideoItem) { _, item in
            guard let item else { return }
            Task { await attachVideoFromGallery(item) }
        }
    }

    private var attachmentPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            PhotosPicker(selection: $selectedVideoItem, matching: .videos, photoLibrary: .shared()) {
                Label("Attach Launch Video", systemImage: "video.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if let videoAttachmentStatus {
                Text(videoAttachmentStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(attachments) { attachment in
                attachmentRow(attachment)
            }
        }
    }

    private func attachmentRow(_ attachment: FlightAttachment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: attachment.kind == .video ? "video.fill" : "doc.fill")
                    .foregroundStyle(attachment.kind == .video ? Color.arcMint : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.fileName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(attachment.kind == .video ? "Launch video" : "Attached file")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if attachment.kind == .video {
                    Button {
                        Task { await analyzeVideoAttachment(attachment) }
                    } label: {
                        if analyzingVideoAttachmentID == attachment.id {
                            ProgressView()
                        } else {
                            Text("Analyze")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .disabled(analyzingVideoAttachmentID != nil)
                }
                Button(role: .destructive) {
                    removeAttachment(attachment)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            if let analysisSummary = attachment.analysisSummary, !analysisSummary.isEmpty {
                Text(analysisSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
    }

    private func removeAttachment(_ attachment: FlightAttachment) {
        if !originalAttachmentIDs.contains(attachment.id) {
            VideoFlightAnalyzer.deleteStoredVideo(for: attachment)
        }
        attachments.removeAll { $0.id == attachment.id }
    }

    private func cancel() {
        attachments
            .filter { !originalAttachmentIDs.contains($0.id) }
            .forEach(VideoFlightAnalyzer.deleteStoredVideo)
        onCancel()
    }

    @MainActor
    private func attachVideoFromGallery(_ item: PhotosPickerItem) async {
        videoAttachmentStatus = "Loading video from Photos..."
        defer { selectedVideoItem = nil }

        do {
            guard let pickedVideo = try await item.loadTransferable(type: PickedFlightVideo.self) else {
                videoAttachmentStatus = "Could not load that video. Try another clip."
                return
            }
            attachments.append(pickedVideo.attachment)
            videoAttachmentStatus = "Attached \(pickedVideo.attachment.fileName). You can analyze it before saving."
        } catch {
            videoAttachmentStatus = error.localizedDescription
        }
    }

    @MainActor
    private func analyzeVideoAttachment(_ attachment: FlightAttachment) async {
        analyzingVideoAttachmentID = attachment.id
        defer { analyzingVideoAttachmentID = nil }

        do {
            let result = try await Task.detached(priority: .utility) {
                try await VideoFlightAnalyzer.analyze(attachment)
            }.value
            guard let index = attachments.firstIndex(where: { $0.id == attachment.id }) else { return }
            attachments[index].analysisSummary = result.summary
            attachments[index].videoEstimatedFlightTimeSeconds = result.durationSeconds.isFinite ? result.durationSeconds : nil
            attachments[index].videoModelConfidence = result.modelConfidence
            if flightTimeSeconds == nil, result.modelConfidence >= 0.55 {
                flightTimeSeconds = result.durationSeconds.rounded()
            }
        } catch {
            videoAttachmentStatus = error.localizedDescription
        }
    }

    private func save() {
        guard let rocket = selectedRocket,
              let mass,
              let altitude,
              let parachute else {
            return
        }
        store.updateFlight(
            id: flight.id,
            rocket: rocket,
            motorDesignation: selectedMotorDesignation,
            mass: mass,
            weather: Weather(
                temperatureF: temperature ?? 0,
                windMPH: wind ?? 0,
                humidityPercent: humidity ?? 0,
                location: location
            ),
            altitude: altitude,
            targetAltitude: wantedAltitude,
            flightTimeSeconds: flightTimeSeconds,
            parachute: parachute,
            reefedCentimeters: reefedCentimeters,
            descentSystem: descentSystem,
            eggStatus: eggStatus,
            notes: notes,
            attachments: attachments,
            round: flight.round
        )
        let keptAttachmentIDs = Set(attachments.map(\.id))
        flight.attachments
            .filter { !keptAttachmentIDs.contains($0.id) }
            .forEach(VideoFlightAnalyzer.deleteStoredVideo)
        onSaved()
    }
}
