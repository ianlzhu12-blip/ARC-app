import SwiftUI
import UniformTypeIdentifiers

struct RocketsView: View {
    @EnvironmentObject private var store: FlightStore
    @State private var teamName = ""
    @State private var school = ""
    @State private var rocketName = ""
    @State private var dryMass = 650.0
    @State private var diameter = 66.0
    @State private var selectedTeamID: UUID?
    @State private var material: RocketMaterial = .cardboard
    @State private var parachuteSize = 18.0
    @State private var defaultMotorDesignation = "F24W-4,7"
    @State private var heightMillimeters = 700.0
    @State private var widthMillimeters = 66.0
    @State private var editingRocketID: UUID?
    @State private var isImportingDesign = false
    @State private var importStatus = ""
    @State private var importedFromOpenRocket = false
    @State private var openRocketFileName: String?
    @State private var openRocketDesignSummary: String?

    private var availableMotors: [MotorSpec] {
        MotorCatalog.motors(for: store.flightMode)
    }

    private var openRocketTypes: [UTType] {
        if let orkType = UTType(filenameExtension: "ork") {
            return [orkType, .xml, .data]
        }
        return [.xml, .data]
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 16) {
                        addTeamCard
                        if editingRocketID == nil {
                            rocketFormCard
                        }
                        rosterCard
                    }
                    .padding()
                    .padding(.bottom, 28)
                }
                .onChange(of: editingRocketID) { _, rocketID in
                    guard let rocketID else { return }
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            scrollProxy.scrollTo(rocketID, anchor: .center)
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
            .navigationTitle("Teams & Rockets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .fileImporter(
                isPresented: $isImportingDesign,
                allowedContentTypes: openRocketTypes,
                allowsMultipleSelection: false
            ) { result in
                importOpenRocketDesign(result)
            }
            .onAppear {
                selectedTeamID = selectedTeamID ?? store.teams.first?.id
                defaultMotorDesignation = availableMotors.first?.designation ?? defaultMotorDesignation
            }
        }
    }

    private var addTeamCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Team")
                .font(.title3.bold())
            TextField("Team name", text: $teamName)
                .fieldStyle()
            TextField("School / organization", text: $school)
                .fieldStyle()
            Button("Save Team") {
                store.addTeam(name: teamName, school: school)
                teamName = ""
                school = ""
                selectedTeamID = store.teams.last?.id
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle()
    }

    private var rocketFormCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Rocket")
                .font(.title3.bold())
            rocketEditorFields
            Button("Save Rocket") {
                saveRocket()
            }
            .buttonStyle(.borderedProminent)
        }
        .cardStyle()
    }

    private var inlineEditRocketForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Edit this rocket", systemImage: "square.and.pencil")
                .font(.headline)
            rocketEditorFields
            HStack {
                Button {
                    saveRocket()
                } label: {
                    Label("Update Rocket", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Cancel") {
                    resetRocketForm()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.arcMint.opacity(0.28)))
    }

    private var rocketEditorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                isImportingDesign = true
            } label: {
                Label("Upload OpenRocket Design", systemImage: "doc.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            if !importStatus.isEmpty {
                Text(importStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if importedFromOpenRocket {
                Label(openRocketFileName ?? "OpenRocket design linked", systemImage: "checkmark.seal.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.arcMint)
            }
            Picker("Team", selection: $selectedTeamID) {
                ForEach(store.teams) { team in
                    Text(team.name).tag(Optional(team.id))
                }
            }
            .pickerStyle(.menu)
            Picker("Material", selection: $material) {
                ForEach(RocketMaterial.allCases) { material in
                    Text(material.displayName).tag(material)
                }
            }
            .pickerStyle(.menu)
            MotorSelectionField(title: "Default Motor", selection: $defaultMotorDesignation, motors: availableMotors)
            TextField("Rocket name", text: $rocketName)
                .fieldStyle()
            NumberField(title: "Dry Mass", value: $dryMass, suffix: "g")
            NumberField(title: "Diameter", value: $diameter, suffix: "mm")
            NumberField(title: "Height", value: $heightMillimeters, suffix: "mm")
            NumberField(title: "Width", value: $widthMillimeters, suffix: "mm")
            NumberField(title: "Parachute", value: $parachuteSize, suffix: "in")
        }
    }

    private var rosterCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Roster")
                .font(.title3.bold())
            ForEach(store.rockets) { rocket in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rocket.name)
                                .font(.headline)
                            if rocket.lockedForNationals {
                                Text("Nationals Locked")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.arcAmber)
                            }
                        }
                        Spacer()
                        Button("Edit") {
                            loadRocketIntoForm(rocket)
                        }
                        .buttonStyle(.bordered)
                        Button("Delete", role: .destructive) {
                            if editingRocketID == rocket.id {
                                resetRocketForm()
                            }
                            store.deleteRocket(id: rocket.id)
                            selectedTeamID = store.teams.first?.id
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("\(Int(rocket.dryMassGrams)) g dry mass • \(Int(rocket.diameterMillimeters)) mm diameter")
                        .foregroundStyle(.secondary)
                    Text("\(rocket.material.displayName) • \(Int(rocket.parachuteSizeInches)) in parachute • \(rocket.defaultMotorDesignation)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if rocket.importedFromOpenRocket {
                        Text("OpenRocket: \(rocket.openRocketFileName ?? "design linked")")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.arcMint)
                    }
                    if editingRocketID == rocket.id {
                        inlineEditRocketForm
                            .transition(.opacity)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                .id(rocket.id)
            }
        }
        .cardStyle()
    }

    private func saveRocket() {
        guard let selectedTeamID else { return }
        if let editingRocketID {
            store.updateRocket(
                id: editingRocketID,
                name: rocketName,
                teamID: selectedTeamID,
                dryMass: dryMass,
                diameter: diameter,
                material: material,
                parachuteSize: parachuteSize,
                defaultMotorDesignation: defaultMotorDesignation,
                heightMillimeters: heightMillimeters,
                widthMillimeters: widthMillimeters,
                importedFromOpenRocket: importedFromOpenRocket,
                openRocketFileName: openRocketFileName,
                openRocketDesignSummary: openRocketDesignSummary
            )
        } else {
            store.addRocket(
                name: rocketName,
                teamID: selectedTeamID,
                dryMass: dryMass,
                diameter: diameter,
                material: material,
                parachuteSize: parachuteSize,
                defaultMotorDesignation: defaultMotorDesignation,
                heightMillimeters: heightMillimeters,
                widthMillimeters: widthMillimeters,
                importedFromOpenRocket: importedFromOpenRocket,
                openRocketFileName: openRocketFileName,
                openRocketDesignSummary: openRocketDesignSummary
            )
        }
        resetRocketForm()
    }

    private func loadRocketIntoForm(_ rocket: Rocket) {
        editingRocketID = rocket.id
        selectedTeamID = rocket.teamID
        rocketName = rocket.name
        dryMass = rocket.dryMassGrams
        diameter = rocket.diameterMillimeters
        material = rocket.material
        parachuteSize = rocket.parachuteSizeInches
        defaultMotorDesignation = rocket.defaultMotorDesignation
        heightMillimeters = rocket.heightMillimeters
        widthMillimeters = rocket.widthMillimeters
        importedFromOpenRocket = rocket.importedFromOpenRocket
        openRocketFileName = rocket.openRocketFileName
        openRocketDesignSummary = rocket.openRocketDesignSummary
        importStatus = rocket.openRocketDesignSummary ?? ""
    }

    private func importOpenRocketDesign(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let design = try OpenRocketImporter.importDesign(from: data, fileName: url.lastPathComponent, fallbackName: rocketName)
            rocketName = design.name
            if let dryMassGrams = design.dryMassGrams {
                dryMass = dryMassGrams
            }
            if let diameterMillimeters = design.diameterMillimeters {
                diameter = diameterMillimeters
            }
            if let height = design.heightMillimeters {
                heightMillimeters = height
            }
            if let width = design.widthMillimeters {
                widthMillimeters = width
            }
            importedFromOpenRocket = true
            openRocketFileName = design.fileName
            openRocketDesignSummary = design.notes
            importStatus = design.notes
        } catch {
            importStatus = error.localizedDescription
        }
    }

    private func resetRocketForm() {
        editingRocketID = nil
        rocketName = ""
        dryMass = 650
        diameter = 66
        material = .cardboard
        parachuteSize = 18
        defaultMotorDesignation = availableMotors.first?.designation ?? "F24W-4,7"
        heightMillimeters = 700
        widthMillimeters = 66
        importStatus = ""
        importedFromOpenRocket = false
        openRocketFileName = nil
        openRocketDesignSummary = nil
    }
}
