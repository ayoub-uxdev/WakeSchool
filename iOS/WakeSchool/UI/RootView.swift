import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Accueil", systemImage: "house.fill") }
            SmartAlarmView()
                .tabItem { Label("Réveil", systemImage: "alarm.fill") }
        }
    }
}