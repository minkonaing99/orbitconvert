import SwiftUI

@main
struct OrbitConvertApp: App {
    @NSApplicationDelegateAdaptor(OrbitConvertAppDelegate.self) private var appDelegate
    @State private var watchedFolders: WatchedFoldersController = {
        let testing = NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Test hosts must not restore personal watched folders or monitor the user's clipboard.
        let defaults = testing ? UserDefaults(suiteName: "OrbitConvert.TestHost.\(UUID().uuidString)") ?? .standard : .standard
        return WatchedFoldersController(defaults: defaults, startClipboard: !testing)
    }()

    var body: some Scene {
        Window(AppIdentity.name, id: "main") {
            ContentView()
                .environment(watchedFolders)
        }
        .defaultSize(width: 760, height: 620)
        Settings {
            CompressionSettingsView()
                .environment(watchedFolders)
        }
        Window("Recent Activity", id: "activity") {
            WatchActivityView().environment(watchedFolders)
        }
        .defaultSize(width: 460, height: 500)
        MenuBarExtra {
            WatchMenuView()
                .environment(watchedFolders)
        } label: {
            Label(watchedFolders.statusTitle, systemImage: watchedFolders.statusSymbol)
                .accessibilityLabel(watchedFolders.accessibilityStatus)
                .help(watchedFolders.accessibilityStatus)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class OrbitConvertAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.updateDockVisibility(hidden: UserDefaults.standard.bool(forKey: "hideDockIcon"))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    static func updateDockVisibility(hidden: Bool) {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        NSApp.setActivationPolicy(hidden ? .accessory : .regular)
    }
}
