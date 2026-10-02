# Remaining document work

The requested improvements are being delivered in stages without replacing the existing conversion, watcher or clipboard engines.

## Completed stages

1. Authorized local Markdown image resources, offline embedding into DOCX/PDF, native external PDF links, and PDF font/page/margin controls. Image resources have path, type, byte, dimension and aggregate pixel limits. Sources remain untouched.
2. Stronger PDF compression with supported external link annotations and nested bookmarks. Bounded action inspection rejects unsupported/chained actions. Candidate output is reopened and its navigation, pages and selectable text are checked before publication. Internal annotation links remain excluded after native destination-remapping validation failed.

Actual implementation and test results are in [implementation](markdown-pdf-implementation.md) and [testing](testing.md).

## Next stage: math, Mermaid and richer styles

- Enable and test editable Pandoc DOCX math first.
- Investigate an offline PDF equation and Mermaid renderer. Pandoc alone does not render Mermaid diagrams; the prior sandboxed WebKit startup failure must be understood before adding a browser-based renderer.
- Pin any required local renderer assets. Disable remote requests, navigation, raw HTML and interactive diagram actions; bound input and execution time.
- Add tests for malformed and oversized expressions, external-resource attempts, ordinary code blocks and embedded output.
- Extend DOCX styling with a validated reference document if needed. Current font/page/margin controls apply only to PDF.
- Resolve internal PDF anchors and internal annotation destinations only with real page-reference tests. Do not silently flatten or discard them.

## Further PDF support

Unsigned forms and other annotations need explicit preservation fixtures before stronger compression can accept them. Tagged content, layers, attachments and named destinations remain protected until semantics can be checked. Signed PDFs must remain excluded from rewriting: modification invalidates their signatures. Encryption/password handling is a separate explicit workflow.

## Compatibility and validation stage

- Add verified architecture-specific Intel helpers if Intel execution is required. Existing bundled document helpers are arm64.
- Run macOS 14 and physical Intel tests on available hardware or VMs; deployment-target compilation alone is insufficient.
- Open representative exports in Preview and available Word/Pages, verify installed sandbox permissions and profile large notes/PDFs.
- Raise meaningful full-app coverage toward 80% without excluding production files or replacing visual validation with implementation-mirroring tests.

Unavailable hardware/application checks must be reported as unverified. No stage should claim those checks passed from structural unit tests alone.
