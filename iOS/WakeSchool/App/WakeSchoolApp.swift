import SwiftUI

@main
struct WakeSchoolApp: App {
    @StateObject private var store = SchoolDataStore(
        environment: AppEnvironment.liveOrFallback()
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // Toucher le widget « Prochain cours » ouvre WakeSchool sur l'emploi du temps.
                .onOpenURL { url in
                    guard url.scheme == "wakeschool",
                          url.host == "widget",
                          url.path == "/next-lesson" else { return }
                    store.requestOpenTimetableFromWidget()
                }
        }
    }
}