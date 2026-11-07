import SwiftUI

@main
struct QuietApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(.primary)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.isConnected {
                ComposeView()
            } else {
                SetupView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.isConnected)
    }
}
