import Foundation

enum MotorCatalog {
    static let arc2026CompetitionInfo = ARCCompetitionInfo(
        seasonYear: 2026,
        sourceName: "American Rocketry Challenge 2026 official resources",
        sourceUpdated: "Rules page crawled April 2026; approved motors PDF dated June 4, 2025",
        altitudeGoalFeet: 750,
        flightTimeRange: 36...39,
        maxLiftOffMassGrams: 650,
        minimumLengthMillimeters: 650,
        minimumBodyDiameterMillimeters: 47,
        qualificationWindow: "July 15, 2025 through March 30, 2026",
        finalsDate: "May 16, 2026",
        finalsLocation: "Great Meadow, The Plains, Virginia"
    )

    static let hobbyMotors: [MotorSpec] = [
        MotorSpec(designation: "1/2A3-2T,4T", manufacturer: "Estes", casing: "13 x 45", propellantMassGrams: 2.0, totalImpulseNS: 1.25, reloadable: false),
        MotorSpec(designation: "A3-2,4,6T", manufacturer: "Estes", casing: "13 x 45", propellantMassGrams: 3.3, totalImpulseNS: 2.50, reloadable: false),
        MotorSpec(designation: "A10-0T", manufacturer: "Estes", casing: "13 x 45", propellantMassGrams: 3.6, totalImpulseNS: 1.88, reloadable: false),
        MotorSpec(designation: "A10-3T,PT", manufacturer: "Estes", casing: "13 x 45", propellantMassGrams: 3.8, totalImpulseNS: 2.50, reloadable: false),
        MotorSpec(designation: "C6-0,3,5,7", manufacturer: "Estes", casing: "18 x 70", propellantMassGrams: 10.8, totalImpulseNS: 9.0, reloadable: false),
        MotorSpec(designation: "C11-0,3,5,7", manufacturer: "Estes", casing: "24 x 70", propellantMassGrams: 12.0, totalImpulseNS: 9.0, reloadable: false),
        MotorSpec(designation: "C12-4,6,8", manufacturer: "QJet/AT", casing: "18 x 70", propellantMassGrams: 10.4, totalImpulseNS: 9.8, reloadable: false),
        MotorSpec(designation: "C18W-4,6,8", manufacturer: "QJet/AT", casing: "18 x 70", propellantMassGrams: 5.6, totalImpulseNS: 9.8, reloadable: false),
        MotorSpec(designation: "D8-0,3,5", manufacturer: "QJet/AT", casing: "24 x 70", propellantMassGrams: 22.0, totalImpulseNS: 18.6, reloadable: false),
        MotorSpec(designation: "D9W-4,7", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 10.1, totalImpulseNS: 20.0, reloadable: true),
        MotorSpec(designation: "D12-0,3,5,7", manufacturer: "Estes", casing: "24 x 70", propellantMassGrams: 21.1, totalImpulseNS: 17.0, reloadable: false),
        MotorSpec(designation: "D13W-4,7,10", manufacturer: "Aerotech", casing: "18 x 70", propellantMassGrams: 9.8, totalImpulseNS: 20.0, reloadable: true),
        MotorSpec(designation: "D15T-4,7", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 8.9, totalImpulseNS: 20.0, reloadable: true),
        MotorSpec(designation: "D16-4,6,8", manufacturer: "QJet/AT", casing: "18 x 79", propellantMassGrams: 12.5, totalImpulseNS: 12.4, reloadable: false),
        MotorSpec(designation: "D20W-4,6,8", manufacturer: "QJet/AT", casing: "18 x 70", propellantMassGrams: 8.7, totalImpulseNS: 13.8, reloadable: false),
        MotorSpec(designation: "D22W-4,7,10", manufacturer: "QJet/AT", casing: "24 x 87", propellantMassGrams: 12.0, totalImpulseNS: 19.3, reloadable: false),
        MotorSpec(designation: "D24T-4,7,10", manufacturer: "Aerotech", casing: "18 x 70", propellantMassGrams: 8.8, totalImpulseNS: 18.5, reloadable: true),
        MotorSpec(designation: "E12-0,4,6,8", manufacturer: "Estes", casing: "24 x 95", propellantMassGrams: 35.9, totalImpulseNS: 27.2, reloadable: false),
        MotorSpec(designation: "E16-0,4,6,8", manufacturer: "Estes", casing: "29 x 114", propellantMassGrams: 40.0, totalImpulseNS: 33.4, reloadable: false),
        MotorSpec(designation: "E16W-4,7", manufacturer: "Aerotech", casing: "29 x 124", propellantMassGrams: 19.0, totalImpulseNS: 40.0, reloadable: true),
        MotorSpec(designation: "E18W-4,8", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 20.7, totalImpulseNS: 39.0, reloadable: true),
        MotorSpec(designation: "E20W-4,7", manufacturer: "Aerotech", casing: "24 x 65", propellantMassGrams: 16.2, totalImpulseNS: 35.0, reloadable: false),
        MotorSpec(designation: "E22SS-13A", manufacturer: "Cesaroni", casing: "24 x 69", propellantMassGrams: 13.4, totalImpulseNS: 24.2, reloadable: true),
        MotorSpec(designation: "E23T-5,8", manufacturer: "Aerotech", casing: "29 x 124", propellantMassGrams: 17.4, totalImpulseNS: 37.0, reloadable: true),
        MotorSpec(designation: "E24C-4,7,10", manufacturer: "Aerotech", casing: "29 x 110", propellantMassGrams: 18.4, totalImpulseNS: 36.3, reloadable: false),
        MotorSpec(designation: "E26W-4,7,10", manufacturer: "QJet/AT", casing: "24 x 70", propellantMassGrams: 18.3, totalImpulseNS: 27.8, reloadable: false),
        MotorSpec(designation: "E28T-4,7", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 18.4, totalImpulseNS: 40.0, reloadable: true),
        MotorSpec(designation: "E30T-4,7", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 17.8, totalImpulseNS: 33.6, reloadable: false),
        MotorSpec(designation: "E30-4,7", manufacturer: "Estes", casing: "24 x 70", propellantMassGrams: 17.8, totalImpulseNS: 33.6, reloadable: false),
        MotorSpec(designation: "E31WT-15A", manufacturer: "Cesaroni", casing: "24 x 69", propellantMassGrams: 11.2, totalImpulseNS: 26.1, reloadable: true),
        MotorSpec(designation: "E35W-5,8,11", manufacturer: "QJet/AT", casing: "24 x 113", propellantMassGrams: 25.4, totalImpulseNS: 39.4, reloadable: false),
        MotorSpec(designation: "E75VM-17A", manufacturer: "Cesaroni", casing: "24 x 69", propellantMassGrams: 10.4, totalImpulseNS: 24.8, reloadable: true),
        MotorSpec(designation: "F15-0,4,6,8", manufacturer: "Estes", casing: "29 x 114", propellantMassGrams: 60.0, totalImpulseNS: 49.6, reloadable: false),
        MotorSpec(designation: "F20W-4,7", manufacturer: "Aerotech", casing: "29 x 73", propellantMassGrams: 30.0, totalImpulseNS: 51.8, reloadable: false),
        MotorSpec(designation: "F22J-5,7", manufacturer: "Aerotech", casing: "29 x 124", propellantMassGrams: 46.3, totalImpulseNS: 65.0, reloadable: true),
        MotorSpec(designation: "F23FJ-4,7", manufacturer: "Aerotech", casing: "29 x 83", propellantMassGrams: 30.0, totalImpulseNS: 41.2, reloadable: false),
        MotorSpec(designation: "F24W-4,7", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 19.0, totalImpulseNS: 50.0, reloadable: true),
        MotorSpec(designation: "F25W-4,6,9", manufacturer: "Aerotech", casing: "29 x 98", propellantMassGrams: 35.6, totalImpulseNS: 80.0, reloadable: false),
        MotorSpec(designation: "F26FJ-6,9", manufacturer: "Aerotech", casing: "29 x 98", propellantMassGrams: 43.1, totalImpulseNS: 62.2, reloadable: false),
        MotorSpec(designation: "F26FJ-6", manufacturer: "Estes", casing: "29 x 98", propellantMassGrams: 43.1, totalImpulseNS: 62.2, reloadable: false),
        MotorSpec(designation: "F27R-4,8", manufacturer: "Aerotech", casing: "29 x 83", propellantMassGrams: 28.4, totalImpulseNS: 49.6, reloadable: false),
        MotorSpec(designation: "F29-12A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 30.9, totalImpulseNS: 54.8, reloadable: true),
        MotorSpec(designation: "F30FJ-4,6,8", manufacturer: "Aerotech", casing: "24 x 90", propellantMassGrams: 31.2, totalImpulseNS: 47.0, reloadable: false),
        MotorSpec(designation: "F30WH/LB-6A", manufacturer: "Cesaroni", casing: "24 x 133", propellantMassGrams: 40.0, totalImpulseNS: 73.1, reloadable: true),
        MotorSpec(designation: "F31CL-12A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 25.7, totalImpulseNS: 55.5, reloadable: true),
        MotorSpec(designation: "F32T-4,6,8", manufacturer: "Aerotech", casing: "24 x 90", propellantMassGrams: 25.8, totalImpulseNS: 56.9, reloadable: false),
        MotorSpec(designation: "F32WH-12A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 29.9, totalImpulseNS: 52.8, reloadable: true),
        MotorSpec(designation: "F35W-5,8,11", manufacturer: "Aerotech", casing: "24 x 95", propellantMassGrams: 30.0, totalImpulseNS: 57.1, reloadable: true),
        MotorSpec(designation: "F36SS-11A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 29.5, totalImpulseNS: 41.2, reloadable: true),
        MotorSpec(designation: "F36BS-14A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 25.6, totalImpulseNS: 51.5, reloadable: true),
        MotorSpec(designation: "F37W-6,10,14", manufacturer: "Aerotech", casing: "29 x 99", propellantMassGrams: 28.2, totalImpulseNS: 50.0, reloadable: true),
        MotorSpec(designation: "F39T-3,6,9", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 22.7, totalImpulseNS: 50.0, reloadable: true),
        MotorSpec(designation: "F40W-4,7,10", manufacturer: "Aerotech", casing: "29 x 124", propellantMassGrams: 40.0, totalImpulseNS: 80.0, reloadable: true),
        MotorSpec(designation: "F41W-5,8,11", manufacturer: "QJet/AT", casing: "24 x 114", propellantMassGrams: 30.0, totalImpulseNS: 45.5, reloadable: false),
        MotorSpec(designation: "F42T-4,8", manufacturer: "Aerotech", casing: "29 x 83", propellantMassGrams: 27.0, totalImpulseNS: 52.9, reloadable: false),
        MotorSpec(designation: "F44W-4,8", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 19.7, totalImpulseNS: 41.5, reloadable: false),
        MotorSpec(designation: "F50T-4,6,9", manufacturer: "Aerotech", casing: "29 x 98", propellantMassGrams: 37.9, totalImpulseNS: 80.0, reloadable: false),
        MotorSpec(designation: "F50T-4,6", manufacturer: "Estes", casing: "29 x 98", propellantMassGrams: 37.9, totalImpulseNS: 80.0, reloadable: false),
        MotorSpec(designation: "F51BS-13A", manufacturer: "Cesaroni", casing: "24 x 101", propellantMassGrams: 22.0, totalImpulseNS: 49.9, reloadable: true),
        MotorSpec(designation: "F51CL-12A", manufacturer: "Cesaroni", casing: "24 x 133", propellantMassGrams: 33.0, totalImpulseNS: 75.0, reloadable: true),
        MotorSpec(designation: "F51NT-10", manufacturer: "Aerotech", casing: "24 x 70", propellantMassGrams: 26.5, totalImpulseNS: 55.1, reloadable: true),
        MotorSpec(designation: "F52C-5,8,12", manufacturer: "Aerotech", casing: "29 x 112", propellantMassGrams: 30.0, totalImpulseNS: 66.2, reloadable: false),
        MotorSpec(designation: "F52T-6,8,11", manufacturer: "Aerotech", casing: "29 x 124", propellantMassGrams: 36.6, totalImpulseNS: 78.0, reloadable: true),
        MotorSpec(designation: "F59WT-12A", manufacturer: "Cesaroni", casing: "29 x 98", propellantMassGrams: 26.1, totalImpulseNS: 57.0, reloadable: true),
        MotorSpec(designation: "F62T-S,M,L", manufacturer: "Aerotech", casing: "29 x 89", propellantMassGrams: 30.5, totalImpulseNS: 51.0, reloadable: true),
        MotorSpec(designation: "F62FJ-10", manufacturer: "Aerotech", casing: "24 x 95", propellantMassGrams: 32.2, totalImpulseNS: 47.6, reloadable: true),
        MotorSpec(designation: "F63R-10", manufacturer: "Aerotech", casing: "24 x 95", propellantMassGrams: 27.6, totalImpulseNS: 49.5, reloadable: true),
        MotorSpec(designation: "F67C-6,9,14", manufacturer: "Aerotech", casing: "29 x 112", propellantMassGrams: 36.8, totalImpulseNS: 77.5, reloadable: false),
        MotorSpec(designation: "F67W-4,6,9", manufacturer: "Aerotech", casing: "29 x 89", propellantMassGrams: 30.0, totalImpulseNS: 61.1, reloadable: false),
        MotorSpec(designation: "F70WT-14A", manufacturer: "Cesaroni", casing: "24 x 101", propellantMassGrams: 22.5, totalImpulseNS: 52.9, reloadable: true),
        MotorSpec(designation: "F79SS-13A", manufacturer: "Cesaroni", casing: "24 x 133", propellantMassGrams: 40.1, totalImpulseNS: 67.8, reloadable: true)
    ]

    static let competitionMotors = hobbyMotors
    static let competitionMotorDesignations = Set(competitionMotors.map(\.designation))

    private static let motorsByDesignation: [String: MotorSpec] = {
        var lookup: [String: MotorSpec] = [:]
        for motor in hobbyMotors + competitionMotors where lookup[motor.designation] == nil {
            lookup[motor.designation] = motor
        }
        return lookup
    }()

    static func motors(for mode: FlightMode) -> [MotorSpec] {
        switch mode {
        case .hobby: return hobbyMotors
        case .competition, .nationals: return competitionMotors
        }
    }

    static func motor(named designation: String) -> MotorSpec? {
        motorsByDesignation[designation]
    }
}
