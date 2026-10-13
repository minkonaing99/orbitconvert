import CryptoKit
import Foundation
import WebKit

nonisolated enum MarkdownGraphicKind: String, Sendable {
    case inlineMath, displayMath, mermaid
}

nonisolated struct MarkdownGraphic: Hashable, Sendable {
    let kind: MarkdownGraphicKind
    let source: String
}

nonisolated struct RenderedGraphic: Sendable {
    let pdf: Data
    let size: CGSize
    /// Distance from the bottom edge to the text baseline; nonzero only for inline math.
    let depth: CGFloat
    /// Display math and diagrams get their own centered paragraph.
    let centered: Bool
}

// Draws TeX (bundled KaTeX) and Mermaid diagrams offline in a hidden WebKit view and returns vector PDF snippets.
// The page allows no network or file access: a strict CSP, a block-all content rule and no navigation beyond the
// initial document. Sources are passed as call arguments, never spliced into the page. Any failure yields nil so
// the caller keeps the source text.
@MainActor
final class MarkdownGraphicsRenderer: NSObject, WKNavigationDelegate {
    static let maxItems = 100
    static let maxMathBytes = 8_192
    static let maxDiagramBytes = 65_536
    static let maxEdge: CGFloat = 4_096
    private static let itemTimeout: Duration = .seconds(10)
    private static let loadTimeout: Duration = .seconds(15)
    private static let totalBudget: Duration = .seconds(60)
    private static let blockAll = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#

    private var loaded: CheckedContinuation<Bool, Never>?
    private var loadedOnce = false
    private var stalled = false

    static func render(_ items: [MarkdownGraphic], fontSize: Double) async -> [RenderedGraphic?] {
        let wanted = items.prefix(maxItems).filter(isWithinLimits)
        let renderer = MarkdownGraphicsRenderer()
        guard !wanted.isEmpty, let view = await renderer.load(
            mermaid: wanted.contains { $0.kind == .mermaid }, fontSize: fontSize) else {
            return items.map { _ in nil }
        }
        let deadline = ContinuousClock.now.advanced(by: totalBudget)
        var results: [MarkdownGraphic: RenderedGraphic] = [:]
        for item in Set(wanted) {
            guard !Task.isCancelled, !renderer.stalled, ContinuousClock.now < deadline else { break }
            results[item] = await renderer.draw(item, in: view)
        }
        return items.enumerated().map { index, item in index < maxItems ? results[item] : nil }
    }

    static func page(fontSize: Double, katexScript: String, katexStyle: String, mermaidScript: String?) -> String? {
        let assets = [katexScript, katexStyle, mermaidScript ?? ""]
        guard !assets.contains(where: { $0.localizedCaseInsensitiveContains("</script") || $0.localizedCaseInsensitiveContains("</style") })
        else { return nil }
        let setup = """
        if (window.mermaid) mermaid.initialize({startOnLoad:false, securityLevel:'strict', htmlLabels:false,
          flowchart:{htmlLabels:false}, maxTextSize:\(maxDiagramBytes), maxEdges:500, theme:'neutral',
          fontFamily:'Helvetica', secure:['secure','securityLevel','startOnLoad','maxTextSize','maxEdges',
          'htmlLabels','flowchart','theme','themeCSS','themeVariables','fontFamily','fontSize']});
        let serial = 0, fontsLoaded = null;
        async function orbitRender(kind, source) {
          // font-display:block draws text invisibly until its face loads, so load every KaTeX face first.
          fontsLoaded = fontsLoaded || Promise.all([...document.fonts].map(face => face.load().catch(() => null)));
          await fontsLoaded;
          const stage = document.getElementById('stage');
          stage.replaceChildren();
          if (kind === 'mermaid') {
            const result = await mermaid.render('orbit' + (serial++), source);
            stage.innerHTML = result.svg;
          } else {
            katex.render(source, stage, {displayMode: kind === 'displayMath', throwOnError: true, trust: false,
              strict: 'ignore', maxSize: 50, maxExpand: 500});
          }
          const marker = document.createElement('span');
          marker.style.cssText = 'display:inline-block;width:0;height:0';
          stage.appendChild(marker);
          await document.fonts.ready;
          const box = stage.getBoundingClientRect(), base = marker.getBoundingClientRect();
          return [box.x, box.y, box.width, box.height, kind === 'inlineMath' ? box.bottom - base.bottom : 0];
        }
        """
        // Only these exact scripts may run (hash-pinned); markup injected into the page cannot execute.
        let scripts = [katexScript] + (mermaidScript.map { [$0] } ?? []) + [setup]
        let hashes = scripts.map { "'sha256-" + Data(SHA256.hash(data: Data($0.utf8))).base64EncodedString() + "'" }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src \(hashes.joined(separator: " ")); \
        style-src 'unsafe-inline'; font-src data:; img-src data:; base-uri 'none'; form-action 'none'">
        <style>\(katexStyle)
        body{margin:0;background:transparent;font:\(fontSize)px Helvetica,sans-serif}
        #stage{display:inline-block;padding:2px}.katex{font-size:1.1em}.katex-display{margin:0}</style>
        \(scripts.map { "<script>" + $0 + "</script>" }.joined())
        </head><body><div id="stage"></div></body></html>
        """
    }

    private static func isWithinLimits(_ item: MarkdownGraphic) -> Bool {
        let limit = item.kind == .mermaid ? maxDiagramBytes : maxMathBytes
        return !item.source.isEmpty && item.source.utf8.count <= limit
    }

    private static func asset(_ name: String, _ ext: String) -> String? {
        Bundle.main.url(forResource: name, withExtension: ext).flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private func load(mermaid: Bool, fontSize: Double) async -> WKWebView? {
        guard let script = Self.asset("katex.min", "js"), let style = Self.asset("katex-inline", "css"),
              let html = Self.page(fontSize: fontSize, katexScript: script, katexStyle: style,
                                   mermaidScript: mermaid ? Self.asset("mermaid.min", "js") : nil),
              let rules = try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "OrbitConvertBlockAll", encodedContentRuleList: Self.blockAll) else { return nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(rules)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: Self.maxEdge, height: Self.maxEdge),
                             configuration: configuration)
        view.navigationDelegate = self
        let ready = await withCheckedContinuation { continuation in
            loaded = continuation
            view.loadHTMLString(html, baseURL: nil)
            Task { @MainActor in
                try? await Task.sleep(for: Self.loadTimeout)
                self.resume(false)
            }
        }
        return ready ? view : nil
    }

    // A stuck script cannot be interrupted, so a timeout abandons the remaining items (they keep their source).
    // The completion-handler call holds no reference to the view, so it and its process go away with render().
    private func draw(_ item: MarkdownGraphic, in view: WKWebView) async -> RenderedGraphic? {
        let outcome: (box: [Double]?, timedOut: Bool) = await withCheckedContinuation { continuation in
            let once = OneShot(continuation)
            view.callAsyncJavaScript("return await orbitRender(kind, source)",
                arguments: ["kind": item.kind.rawValue, "source": item.source], in: nil, in: .page) { result in
                once.resume(((try? result.get()) as? [Double], false))
            }
            Task { @MainActor in
                try? await Task.sleep(for: Self.itemTimeout)
                once.resume((nil, true))
            }
        }
        if outcome.timedOut { stalled = true }
        let box = outcome.box
        let maxEdge = Self.maxEdge
        guard let box, box.count == 5, box.allSatisfy(\.isFinite), box[2] > 0, box[3] > 0,
              box[2] <= maxEdge, box[3] <= maxEdge else { return nil }
        let configuration = WKPDFConfiguration()
        configuration.rect = CGRect(x: box[0], y: box[1], width: box[2], height: box[3])
        guard let pdf = try? await view.pdf(configuration: configuration) else { return nil }
        return RenderedGraphic(pdf: pdf, size: CGSize(width: box[2], height: box[3]), depth: max(0, box[4]),
                               centered: item.kind != .inlineMath)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        let initial = !loadedOnce && navigationAction.request.url?.absoluteString == "about:blank"
        loadedOnce = true
        decisionHandler(initial ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { resume(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { resume(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) { resume(false) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { resume(false) }

    private func resume(_ value: Bool) {
        loaded?.resume(returning: value)
        loaded = nil
    }
}

@MainActor
private final class OneShot<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
