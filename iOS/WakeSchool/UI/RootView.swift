import SwiftUI

struct RootView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore

    @State private var showingPronoteLogin = false

    var body: some View {
        Group {
            mainInterface
        }
        .task {
            await dataStore.start()

            if dataStore.dataSource == .demo {
                showingPronoteLogin = true
            }
        }
        .sheet(isPresented: $showingPronoteLogin) {
            PronoteLoginView()
                .environmentObject(dataStore)
        }
    }

    private var mainInterface: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }

            TimetableView()
                .tabItem {
                    Label("Emploi du temps", systemImage: "calendar")
                }

            HomeworkView()
                .tabItem {
                    Label("Devoirs", systemImage: "book.closed.fill")
                }

            GradesView()
                .tabItem {
                    Label("Notes", systemImage: "chart.bar.fill")
                }

            SmartAlarmView()
                .tabItem {
                    Label("Réveil", systemImage: "alarm.fill")
                }
        }
    }
}