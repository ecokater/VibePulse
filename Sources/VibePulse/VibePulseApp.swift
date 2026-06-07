import SwiftUI

@main
struct VibePulseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.isAwake ? "cup.and.heat.waves.fill" : "cup.and.heat.waves")
        }
        .menuBarExtraStyle(.window)
    }
}
