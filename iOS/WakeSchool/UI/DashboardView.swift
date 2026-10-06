import SwiftUI

/// Placeholder du Dashboard. Le contenu réel viendra dans une tâche dédiée.
struct DashboardView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo.opacity(0.9), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "alarm.waves.left.and.right")
                    .font(.system(size: 56))
                Text("WakeSchool")
                    .font(.largeTitle.bold())
                Text("Dashboard à venir")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
        }
    }
}

#Preview { DashboardView() }
