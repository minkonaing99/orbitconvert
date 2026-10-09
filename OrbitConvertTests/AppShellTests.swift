import XCTest
import AppKit
import SwiftUI
import UniformTypeIdentifiers
@testable import OrbitConvert

final class AppShellTests: XCTestCase {
    @MainActor
    func testClosingWindowKeepsMenuBarAppRunning() {
        XCTAssertFalse(OrbitConvertAppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    }

    @MainActor
    func testDockPreferenceDoesNotChangeTestHostActivationPolicy() {
        let original = NSApplication.shared.activationPolicy()
        OrbitConvertAppDelegate.updateDockVisibility(hidden: true)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), original)
        OrbitConvertAppDelegate.updateDockVisibility(hidden: false)
        XCTAssertEqual(NSApplication.shared.activationPolicy(), original)
    }

    @MainActor
    func testSelectedFilesFitCompactWindow() throws {
        let files = ["Screenshot with a long filename.png", "certifications.png"].map { name in
            FileItem(url: URL(fileURLWithPath: "/tmp/" + name), fileName: name,
                     fileExtension: "png", contentTypeIdentifier: UTType.png.identifier,
                     contentTypeName: "PNG image", fileSize: 812_000, creationDate: nil,
                     pixelWidth: 100, pixelHeight: 100, pageCount: nil, thumbnailData: Data(),
                     supportedConversions: [.jpeg, .heic, .tiff])
        }
        let view = NSHostingView(rootView: ContentView(files: files))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 620, height: 460),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: .darkAqua)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(view.fittingSize.width, 620)
        XCTAssertLessThanOrEqual(view.fittingSize.height, 460)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = "Compact selected-file window"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testWatchedSettingsEmptyAndPopulatedLayouts() throws {
        let suite = "WatchedSettingsLayout.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let watcher = WatchedFoldersController(defaults: defaults)
        for populated in [false, true] {
            if populated {
                watcher.folders = [WatchedFolder(displayName: "Screenshots and exported images",
                    bookmarkData: Data(), isEnabled: false)]
                watcher.activity = [
                    WatchActivity(fileName: "A very long screenshot filename from the previous session.jpg",
                        outcome: .optimized, originalBytes: 8_000_000, outputBytes: 2_000_000),
                    WatchActivity(fileName: "document.pdf", outcome: .skipped, message: "No useful reduction"),
                    WatchActivity(fileName: "unavailable.png", outcome: .failed,
                        message: "Folder access expired. Grant access again in Settings.")
                ]
            }
            for dark in [false, true] {
                try capture(WatchedFoldersSettingsView().environment(watcher),
                    width: 550, height: 390, dark: dark,
                    name: "Watched settings \(populated ? "populated" : "empty") \(dark ? "dark" : "light")")
            }
        }
        try capture(WatchActivityView().environment(watcher), width: 460, height: 500,
                    dark: true, name: "Previous file activity")
    }

    @MainActor
    private func capture<V: View>(_ root: V, width: CGFloat, height: CGFloat,
                                 dark: Bool, name: String) throws {
        let view = NSHostingView(rootView: root
            .frame(width: width, height: height)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = view
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertLessThanOrEqual(view.fittingSize.width, width)
        XCTAssertLessThanOrEqual(view.fittingSize.height, height)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: UTType.png.identifier)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testAppIdentityMatchesBundleConfiguration() {
        XCTAssertEqual(AppIdentity.name, Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.example.OrbitConvert")
    }
}
