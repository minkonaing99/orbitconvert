import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ControlsRenderingTests: XCTestCase {
    @MainActor
    func testActionEditorRendersEveryActionKindAndReplacement() throws {
        var actions = AutomationActionKind.allCases.map { AutomationAction(kind: $0) }
        actions += ReplacementBehavior.allCases.map { AutomationAction(kind: .compress, replacement: $0) }
        actions.append(AutomationAction(kind: .convert, format: "png"))
        actions.append(AutomationAction(kind: .rename, template: "'unclosed"))
        for (index, original) in actions.enumerated() {
            var action = original
            try render(AutomationActionEditor(action: Binding(get: { action }, set: { action = $0 })),
                       width: 640, height: 260, dark: index.isMultiple(of: 2))
            XCTAssertEqual(action, original, "Rendering must not change the action")
        }
    }

    @MainActor
    func testMenuRendersSavedActivityPausedAndEmpty() throws {
        let rule = AutomationRunDetails(ruleName: "Organize", finalName: "Note_1.txt", destination: "/tmp/out",
            steps: [AutomationStepRecord(action: "Rename", inputName: "a.txt", outputName: "Note_1.txt",
                destination: "/tmp", message: "Renamed", failed: false),
                AutomationStepRecord(action: "Move to folder", inputName: "Note_1.txt", outputName: "Note_1.txt",
                destination: "/tmp/out", message: "Destination unavailable", failed: true)],
            dateFallback: true, compressionOriginalBytes: 0, compressionSavedBytes: 0)
        let activity = [
            WatchActivity(fileName: "photo.jpg", outcome: .optimized, originalBytes: 2_000_000, outputBytes: 1_200_000),
            WatchActivity(fileName: "scan.pdf", outcome: .skipped, message: "No useful reduction"),
            WatchActivity(fileName: "a.txt", outcome: .failed, message: "Move failed", automation: rule)]
        for (paused, history) in [(true, activity), (false, [WatchActivity]())] {
            let suite = "OrbitConvert.MenuRender.\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(try JSONEncoder().encode(history), forKey: "watchedActivity")
            defaults.set(paused, forKey: "watchingPaused")
            let watcher = WatchedFoldersController(defaults: defaults)
            try render(WatchMenuView().environment(watcher), width: 350, height: 640, dark: paused)
            try render(WatchActivityView().environment(watcher), width: 460, height: 500, dark: !paused)
        }
    }

    @MainActor
    func testActionControlsRenderForEachSelectionType() throws {
        let jpeg = item("photo.jpg", UTType.jpeg.identifier, [.png, .heic, .tiff])
        let png = item("shot.png", UTType.png.identifier, [.jpeg, .tiff])
        let pdf = item("doc.pdf", UTType.pdf.identifier, [], pages: 3)
        let markdown = item("note.md", "net.daringfireball.markdown", [])
        let suite = "OrbitConvert.ControlsRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var busy = false
        for selection in [[jpeg], [jpeg, png], [pdf], [pdf, pdf], [markdown], [jpeg, pdf]] {
            try render(ConversionControlsView(file: selection[0], selection: selection,
                onBusyChanged: { busy = $0 }).defaultAppStorage(defaults), width: 620, height: 420, dark: selection.count > 1)
        }
        XCTAssertFalse(busy)
    }

    @MainActor
    func testQuickCompressionWindowOpensWithSavedModeAndCloses() throws {
        let suite = "OrbitConvert.QuickRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(QuickCompressionMode.chooseFolder.rawValue, forKey: "quickCompressionMode")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("photo.jpg")
        try Data("not compressed yet".utf8).write(to: source)
        let controller = QuickCompressionController(sources: [source], defaults: defaults)
        var closed = false
        controller.onClose = { closed = true }
        XCTAssertEqual(controller.mode, .chooseFolder)
        controller.show()
        defer { controller.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(NSApp.windows.contains { $0.title == "Compress with OrbitConvert" && $0.isVisible })
        controller.close()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(closed)
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(try Data(contentsOf: source), Data("not compressed yet".utf8))
    }

    private func item(_ name: String, _ type: String, _ conversions: [ConversionFormat], pages: Int? = nil) -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/tmp/" + name), fileName: name,
            fileExtension: (name as NSString).pathExtension, contentTypeIdentifier: type,
            contentTypeName: type, fileSize: 2_000_000, creationDate: nil,
            pixelWidth: pages == nil ? 1920 : 612, pixelHeight: pages == nil ? 1080 : 792, pageCount: pages,
            thumbnailData: Data(), supportedConversions: conversions)
    }
}
