import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Run outside the measured process so fixture generation does not inflate its baseline.
let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/orbit-memory-fixtures")
guard root.isFileURL, !FileManager.default.fileExists(atPath: root.path) else {
    fatalError("Choose a new fixture directory; existing data is never replaced.")
}
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])

func image(width: Int, height: Int, seed: Int) throws -> CGImage {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let data = context.data else {
        throw NSError(domain: "Fixture", code: 1)
    }
    let pixels = data.assumingMemoryBound(to: UInt8.self)
    var random = UInt32(seed + 1)
    for y in 0..<height {
        for x in 0..<width {
            random = random &* 1_664_525 &+ 1_013_904_223
            let offset = (y * width + x) * 4
            pixels[offset] = UInt8(truncatingIfNeeded: x / 13 + Int(random >> 28))
            pixels[offset + 1] = UInt8(truncatingIfNeeded: y / 11 + Int(random >> 27))
            pixels[offset + 2] = UInt8(truncatingIfNeeded: (x + y) / 19 + seed * 17)
            pixels[offset + 3] = 255
        }
    }
    guard let result = context.makeImage() else { throw NSError(domain: "Fixture", code: 2) }
    return result
}

for (name, width, height, count) in [("images24", 6000, 4000, 12), ("images48", 8000, 6000, 4)] {
    let directory = root.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    for index in 0..<count {
        try autoreleasepool {
            let url = directory.appendingPathComponent("image-\(index).jpg")
            let bitmap = try image(width: width, height: height, seed: index)
            guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw NSError(domain: "Fixture", code: 3)
            }
            CGImageDestinationAddImage(destination, bitmap, [kCGImageDestinationLossyCompressionQuality: 0.98] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "Fixture", code: 4) }
        }
    }
}
let pdfs = root.appendingPathComponent("pdfs")
try FileManager.default.createDirectory(at: pdfs, withIntermediateDirectories: false)
for fileIndex in 0..<3 {
    try autoreleasepool {
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let document = CGContext(pdfs.appendingPathComponent("document-\(fileIndex).pdf") as CFURL,
                                      mediaBox: &box, nil) else { throw NSError(domain: "Fixture", code: 5) }
        for page in 0..<20 {
            try autoreleasepool {
                document.beginPDFPage(nil)
                document.draw(try image(width: 1600, height: 2000, seed: fileIndex * 20 + page),
                              in: CGRect(x: 30, y: 30, width: 552, height: 690))
                let text = NSAttributedString(string: "Memory profile document \(fileIndex), page \(page)",
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)])
                document.textPosition = CGPoint(x: 30, y: 750)
                CTLineDraw(CTLineCreateWithAttributedString(text), document)
                document.endPDFPage()
            }
        }
        document.closePDF()
    }
}
print(root.path)
