import SwiftUI

@main
struct OrbitConvertApp: App {
    var body: some Scene {
        WindowGroup(AppIdentity.name) {
            ContentView()
        }
        .defaultSize(width: 680, height: 480)
        Settings {
            CompressionSettingsView()
        }
    }
}
