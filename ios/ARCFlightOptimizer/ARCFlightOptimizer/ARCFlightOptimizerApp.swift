import SwiftUI

@main
struct ARCFlightOptimizerApp: App {
    @StateObject private var store = FlightStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
