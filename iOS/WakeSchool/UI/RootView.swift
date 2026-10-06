import SwiftUI

enum AppTab: Hashable {
    case home
    case timetable
    case homework
    case grades
    case alarm
}

struct RootView: View {
    @EnvironmentObject private var store: SchoolDataStore
    @State private var tab: AppTab = .home

    var body: some View {
        TabView(selection: $tab) {
            DashboardView(onNavigate: { tab = $0 })
                .tabItem { Label("Accueil", systemImage: "house.fill") }
                .tag(AppTab.home)
            TimetableView()
                .tabItem { Label("Emploi du temps", systemImage: "calendar") }
                .tag(AppTab.timetable)
            HomeworkView()
                .tabItem { Label("Devoirs", systemImage: "checklist") }
                .badge(HomeworkService.overdue(store.snapshot.homework, now: Date()).count)
                .tag(AppTab.homework)
            GradesView()
                .tabItem { Label("Notes", systemImage: "chart.bar.fill") }
                .tag(AppTab.grades)
            SmartAlarmView()
                .tabItem { Label("Réveil", systemImage: "alarm.fill") }
                .tag(AppTab.alarm)
        }
        .tint(WakeTheme.accent)
        .preferredColorScheme(.dark)
        .task { await store.start() }
    }
}
