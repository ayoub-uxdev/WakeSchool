import SwiftUI

struct RootView: View {
    @EnvironmentObject private var dataStore: SchoolDataStore

    @State private var showingPronoteLogin = false
    @State private var selectedTab = 0

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
        // Deep link depuis le widget : ouvrir l'onglet Emploi du temps.
        .onChange(of: dataStore.widgetOpenTimetable) { _, newValue in
            if newValue {
                selectedTab = 1
                dataStore.acknowledgeWidgetOpenTimetableRequest()
            }
        }
    }

    private var mainInterface: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Accueil", systemImage: "house.fill")
                }
                .tag(0)

            TimetableView()
                .tabItem {
                    Label("Emploi du temps", systemImage: "calendar")
                }
                .tag(1)

            AcademicCalendarView(dataStore: dataStore)
                .tabItem {
                    Label("Calendrier", systemImage: "calendar.circle.fill")
                }
                .tag(2)

            HomeworkView()
                .tabItem {
                    Label("Devoirs", systemImage: "book.closed.fill")
                }
                .tag(3)

            GradesView()
                .tabItem {
                    Label("Notes", systemImage: "chart.bar.fill")
                }
                .tag(4)

            MoreView()
                .tabItem {
                    Label("Plus", systemImage: "ellipsis.circle.fill")
                }
                .tag(5)
        }
    }
}