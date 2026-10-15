import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import OrbitConvert

final class ViewRenderingTests: XCTestCase {
    @MainActor
    func testTargetSizeSheetFitsAndDoesNotRunOnOpen() throws {
        var ran = false
        for dark in [false, true] {
            try render(TargetSizeOptionsView(count: 2, onCancel: {}, onRun: { _ in ran = true }),
                       width: 420, height: 360, dark: dark)
        }
        XCTAssertFalse(ran)
    }

    @MainActor
    func testResizeSheetRendersEveryPresetWithoutRunning() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try writeJPEG(width: 1600, height: 900, in: folder)
        let file = FileItem(url: url, fileName: url.lastPathComponent, fileExtension: "jpg",
            contentTypeIdentifier: UTType.jpeg.identifier, contentTypeName: "JPEG image",
            fileSize: 10_000, creationDate: nil, pixelWidth: 1600, pixelHeight: 900, pageCount: nil,
            thumbnailData: Data(), supportedConversions: [.png])
        var ran = false
        for preset in ResizePreset.allCases {
            var options = ResizeOptions()
            options.preset = preset
            var compression = CompressionPreset.balanced
            let view = ResizeOptionsView(files: [file],
                options: Binding(get: { options }, set: { options = $0 }),
                compressionPreset: Binding(get: { compression }, set: { compression = $0 }),
                onCancel: {}, onRun: { ran = true })
            try render(view, width: 480, height: 560, dark: preset == .custom, settle: 0.5)
        }
        XCTAssertFalse(ran)
    }

    @MainActor
    func testRulesListRendersLegacyAndCustomRulesWithoutSaving() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var saved = false, ran = false
        let legacy = try watchedFolder(folder, rules: nil)
        let custom = try watchedFolder(folder, rules: [
            AutomationRule(name: "Rename screenshots", actions: [AutomationAction(kind: .rename)]),
            AutomationRule(name: "Disabled", isEnabled: false, actions: [AutomationAction(kind: .compress)])])
        for (index, watched) in [legacy, custom].enumerated() {
            try render(AutomationRulesView(folder: watched, canRun: index == 0,
                onSave: { _ in saved = true }, onRun: { _ in ran = true }),
                width: 680, height: 520, dark: index == 1)
        }
        XCTAssertFalse(saved)
        XCTAssertFalse(ran)
    }

    @MainActor
    func testPreviewRendersForReadableAndMissingFolderWithoutChangingFiles() throws {
        let folder = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("note".utf8).write(to: folder.appendingPathComponent("note.txt"))
        let rule = AutomationRule(name: "Rename text", conditions: [AutomationCondition(value: "txt")],
            actions: [AutomationAction(kind: .rename, template: "'Note'_{i}.{ext}")])
        try render(AutomationPreviewView(folder: watchedFolder(folder, rules: [rule]), rule: rule),
                   width: 700, height: 520, dark: false, settle: 1)
        let missing = WatchedFolder(displayName: "Missing", bookmarkData: Data([1, 2, 3]))
        try render(AutomationPreviewView(folder: missing), width: 700, height: 520, dark: true, settle: 0.5)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("note.txt").path))
    }

    @MainActor
    func testClipboardSettingsRenderWithIsolatedDefaults() throws {
        let suite = "OrbitConvert.ClipboardSettingsRender.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["com.apple.Preview"], forKey: "clipboardIgnoredApps")
        let watcher = WatchedFoldersController(defaults: defaults)
        for dark in [false, true] {
            try render(ClipboardSettingsView().environment(watcher), width: 590, height: 480, dark: dark, scrolls: true)
        }
    }

    @MainActor
    func testClipboardResultPanelShowsAndCloses() throws {
        let thumbnail = try pngData(width: 64, height: 64)
        let result = ClipboardOptimizationResult(data: Data(count: 600), typeIdentifier: UTType.png.identifier,
            originalBytes: 1_000, width: 1024, height: 768, thumbnailData: thumbnail, duration: 0.2,
            sourceFingerprint: "a", outputFingerprint: "b", fileBacked: true)
        var actions: [String] = []
        let panel = ClipboardResultPanel(result: result, copy: { actions.append("copy") },
            save: { actions.append("save") }, reveal: { actions.append("reveal") }, onClose: { actions.append("close") })
        panel.show()
        defer { panel.close() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(NSApp.windows.contains { isResultCard($0) && $0.isVisible })
        panel.close()
        XCTAssertFalse(NSApp.windows.contains { isResultCard($0) && $0.isVisible })
        XCTAssertEqual(actions, [])
    }

    @MainActor
    func testClipboardResultPanelDismissesItself() throws {
        let result = ClipboardOptimizationResult(data: Data(count: 600), typeIdentifier: UTType.png.identifier,
            originalBytes: 1_000, width: 1024, height: 768, thumbnailData: try pngData(width: 64, height: 64), duration: 0.2,
            sourceFingerprint: "a", outputFingerprint: "b", fileBacked: false)
        var actions: [String] = []
        let panel = ClipboardResultPanel(result: result, copy: {}, save: {}, reveal: {},
                                         onClose: { actions.append("close") }, autoDismiss: .milliseconds(300))
        defer { panel.close() }
        panel.show()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertTrue(NSApp.windows.contains { isResultCard($0) && $0.isVisible })
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        XCTAssertFalse(NSApp.windows.contains { isResultCard($0) && $0.isVisible }, "The card goes away by itself")
        XCTAssertEqual(actions, ["close"])
    }

    @MainActor
    private func isResultCard(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)) == "ClipboardResultWindow"
    }

    private func watchedFolder(_ url: URL, rules: [AutomationRule]?) throws -> WatchedFolder {
        var folder = WatchedFolder(displayName: url.lastPathComponent,
            bookmarkData: try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil))
        folder.rules = rules
        return folder
    }

    private func writeJPEG(width: Int, height: Int, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("photo.jpg")
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
