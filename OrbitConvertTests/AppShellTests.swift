import XCTest
import AppKit
import SwiftUI
import UniformTypeIdentifiers
@testable import OrbitConvert

final class AppShellTests: XCTestCase {
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

    func testAppIdentityMatchesBundleConfiguration() {
        XCTAssertEqual(AppIdentity.name, Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.example.OrbitConvert")
    }
}
