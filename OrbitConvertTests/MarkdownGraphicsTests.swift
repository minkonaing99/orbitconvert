import PDFKit
import XCTest
@testable import OrbitConvert

@MainActor
final class MarkdownGraphicsTests: XCTestCase {
    func testRendersMathAndMermaidAsVectorPDF() async throws {
        let items = [MarkdownGraphic(kind: .inlineMath, source: "e^{i\\pi}+1=0"),
                     MarkdownGraphic(kind: .displayMath, source: "\\int_0^1 x^2\\,dx = \\frac{1}{3}"),
                     MarkdownGraphic(kind: .mermaid, source: "graph TD\n  A[Start] --> B[Done]")]

        let rendered = await MarkdownGraphicsRenderer.render(items, fontSize: 12)

        XCTAssertEqual(rendered.count, 3)
        for (index, graphic) in rendered.enumerated() {
            let result = try XCTUnwrap(graphic, "item \(index)")
            XCTAssertEqual(result.pdf.prefix(4), Data("%PDF".utf8))
            XCTAssertNotNil(PDFDocument(data: result.pdf)?.page(at: 0))
            XCTAssertGreaterThan(result.size.width, 4)
            XCTAssertGreaterThan(result.size.height, 4)
        }
        let inline = try XCTUnwrap(rendered[0]), display = try XCTUnwrap(rendered[1])
        XCTAssertGreaterThan(inline.depth, 0, "Inline math sits on the text baseline")
        XCTAssertLessThan(inline.depth, inline.size.height)
        XCTAssertGreaterThan(display.size.height, inline.size.height)
    }

    func testInvalidOversizedAndExcessItemsFallBack() async throws {
        let valid = MarkdownGraphic(kind: .inlineMath, source: "x^2")
        let items = [MarkdownGraphic(kind: .inlineMath, source: "\\frac{"),
                     MarkdownGraphic(kind: .displayMath, source: String(repeating: "x+", count: 4_200)),
                     MarkdownGraphic(kind: .mermaid, source: "this is not a diagram ]]["),
                     MarkdownGraphic(kind: .inlineMath, source: "\\href{https://example.com}{x}")]
            + Array(repeating: valid, count: MarkdownGraphicsRenderer.maxItems)

        let rendered = await MarkdownGraphicsRenderer.render(items, fontSize: 12)

        XCTAssertEqual(rendered.count, items.count)
        XCTAssertNil(rendered[0], "Invalid TeX keeps its source text")
        XCTAssertNil(rendered[1], "Equations over 8 KiB are not rendered")
        XCTAssertNil(rendered[2], "Invalid diagrams keep their source")
        XCTAssertNotNil(rendered[4])
        XCTAssertNil(rendered.last ?? nil, "Only the first \(MarkdownGraphicsRenderer.maxItems) items render")
    }

    func testPageBlocksEveryResourceAndRejectsUnsafeAssets() throws {
        let page = try XCTUnwrap(MarkdownGraphicsRenderer.page(fontSize: 12, katexScript: "", katexStyle: "",
                                                               mermaidScript: nil))
        XCTAssertTrue(page.contains("default-src 'none'"))
        XCTAssertFalse(page.contains("unsafe-eval"))
        XCTAssertFalse(page.contains("script-src 'unsafe-inline'"), "Only the page's own scripts may run")
        XCTAssertTrue(page.contains("script-src 'sha256-"))
        XCTAssertTrue(page.contains("base-uri 'none'") && page.contains("form-action 'none'"))
        XCTAssertFalse(page.contains("://"), "No remote or file URLs in the page")
        XCTAssertNil(MarkdownGraphicsRenderer.page(fontSize: 12, katexScript: "a</script>b", katexStyle: "",
                                                   mermaidScript: nil))
    }

    func testPDFExportDrawsFormulasAndDiagramsInsteadOfSource() async throws {
        let job = try BundledDocumentTool.workspace()
        defer { try? FileManager.default.removeItem(at: job) }
        let url = job.appendingPathComponent("math.md")
        let markdown = "Euler: $e^{i\\pi}+1=0$ inline.\n\n$$\\frac{a}{b} = \\int_0^1 x\\,dx$$\n\n"
            + "```mermaid\ngraph TD\n  Alpha --> Beta\n```\n\nPrice $5 and $10.\n"
        try Data(markdown.utf8).write(to: url)
        let file = try XCTUnwrap(FileTypeService().inspect([url]).files.first)

        let report = try await MarkdownConversionService().convert(file, toDOCX: false, in: job)

        let text = try XCTUnwrap(PDFDocument(url: try XCTUnwrap(report.outputURLs.first))?.string)
        XCTAssertFalse(text.contains("\\frac"), "Complex TeX must be drawn, not printed as source")
        XCTAssertFalse(text.contains("-->"), "Mermaid source must be drawn as a diagram")
        XCTAssertTrue(text.contains("Euler"))
        XCTAssertTrue(text.contains("Price $5 and $10."))
    }
}
