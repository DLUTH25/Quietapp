import SwiftUI

@main
struct LockInApp: App {
    @StateObject private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .tint(.orange)
        }
        .onChange(of: scenePhase) { _, phase in
            // Re-check the date when the app comes back, so a new day/week starts a new list.
            if phase == .active { store.now = Date() }
        }
    }
}

@MainActor
struct RootView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(store.activePeriod == .day ? "Today" : "This week", systemImage: "bolt.fill") }
            TasksView()
                .tabItem { Label("Tasks", systemImage: "list.bullet") }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            store.now = Date()
        }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
