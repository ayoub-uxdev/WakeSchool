import SwiftUI

@main
struct WakeSchoolApp: App {
    @StateObject private var store = SchoolDataStore(environment: AppEnvironment.liveOrFallback())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
