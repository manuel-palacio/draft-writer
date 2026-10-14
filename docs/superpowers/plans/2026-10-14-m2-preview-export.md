# Draft Writer M2 (Reading and output) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A live preview pane (⌘R), plus File > Export as HTML…, File > Export as PDF… and File > Print….

**Architecture:**
- `DraftKit.PreviewRenderer` turns Markdown into HTML with cmark-gfm (pure and unit-tested).
- The app shows that HTML in a `WKWebView`.
- A `WKURLSchemeHandler` for `draft-asset://` serves document-relative images and the bundled fonts from the app process, so the sandbox and WebKit's file-access rules stay simple.
- Export reuses the same page. PDF and Print go through `WKWebView.printOperation`, which paginates.

**Tech Stack:** cmark-gfm (swift-cmark: `cmark-gfm`, `cmark-gfm-extensions`), WebKit, PDFKit (tests), SwiftUI `FocusedValue` for menu commands.

**Spec:** `docs/superpowers/specs/2026-10-14-draft-design.md` (section "M2 — Reading and output")

## Global Constraints

- All M1 global constraints still apply (macOS 15, Swift 6, UTF-16 `NSRange`s, commit trailer).
- Markdown to HTML goes through cmark-gfm with the GFM extensions table, strikethrough, autolink and
  tasklist, and with `CMARK_OPT_SOURCEPOS`. Raw HTML stays omitted (cmark's safe default).
- Preview: 300 ms debounce. Content JavaScript is disabled (`allowsContentJavaScript = false`). Updates
  replace the `#content` element through `evaluateJavaScript`, without reloading. Link clicks open in
  the default browser.
- Export never modifies the source document. Exported HTML is self-contained: the CSS and the iA Duo
  fonts are inlined, and images stay as relative links. PDF page size is A4 by default, with Letter as
  a setting, and 2 cm margins.
- The stylesheet uses the iA fonts, the same text width as the editor, and `prefers-color-scheme` for
  dark mode in the preview. Exports always print light.

## Review Focus

1. **Text that looks like HTML (`a < b`, `<script>`)** must render as text or be omitted, never execute.
   Pinned in Task 1 (`escapesAngleBrackets`, `omitsRawScript`).
2. **Asset paths that escape the document folder (`../../etc/passwd`, absolute paths)** must be refused
   by the scheme handler. Pinned in Task 2 (`rejectsTraversal`, `rejectsAbsolute`).
3. **Unsaved documents (no folder)** must still preview; relative images then don't load. Pinned in
   Task 2 (`noFolderResolvesNothing`).
4. **Long documents in the PDF** must paginate onto real A4 pages. Pinned in Task 4 (`pdfIsPaginatedA4`).
5. **Typing fast while the preview is open** must not reload the page or pile up renders. Pinned in
   Task 3 (`updateKeepsSamePageLoad`) and by the debounce.

---

## File Structure

```
Packages/DraftKit/Sources/DraftKit/PreviewRenderer.swift   Markdown → HTML body / full page
Packages/DraftKit/Tests/DraftKitTests/PreviewRendererTests.swift
DraftWriter/Preview/preview.css                             stylesheet (resource)
DraftWriter/Preview/PreviewAssets.swift                     CSS + font loading; draft-asset URL mapping
DraftWriter/Preview/AssetSchemeHandler.swift                WKURLSchemeHandler
DraftWriter/Preview/PreviewView.swift                       NSViewRepresentable WKWebView + coordinator
DraftWriter/Export/Exporter.swift                           HTML string, PDF file, print
DraftWriter/App/ExportCommands.swift                        File menu items, FocusedValue plumbing
DraftWriterTests/PreviewTests.swift, ExportTests.swift
```

### Task 1: PreviewRenderer

**Files:** Create `Sources/DraftKit/PreviewRenderer.swift` and `Tests/DraftKitTests/PreviewRendererTests.swift`.
Modify `Package.swift` to add `.package(url: "https://github.com/swiftlang/swift-cmark.git", from: "0.6.0")`,
with the products `cmark-gfm` and `cmark-gfm-extensions` in the `DraftKit` target.

**Interfaces:**
- Produces:
  ```swift
  public enum PreviewRenderer {
      public static func body(for markdown: String) -> String                    // HTML fragment
      public static func page(for markdown: String, title: String, css: String) -> String
      public static func line(atUTF16Offset offset: Int, in text: String) -> Int  // 1-based source line
  }
  ```
  `page` returns `<!doctype html>`, a `<meta charset="utf-8">`, an escaped `<title>`, `<style>` with the
  css, and the body inside `<article id="content">…</article>`.

- [ ] **Step 1: Write the failing tests:**
  - `heading`: `"# Hi *there*"` → contains `<h1 data-sourcepos="1:1-1:12">Hi <em>there</em></h1>`.
  - `escapesAngleBrackets`: `"a < b & c"` → contains `a &lt; b &amp; c`.
  - `omitsRawScript`: `"<script>alert(1)</script>"` → does not contain `<script>`.
  - `table`: `"|a|b|\n|-|-|\n|1|2|"` → contains `<table` and `<td>1</td>`.
  - `strikethroughAndTasks`: `"~~x~~\n\n- [x] done"` → contains `<del>x</del>` and `checked=""`.
  - `pageEscapesTitle`: `page(for: "x", title: "A<B", css: "p{}")` → contains `<title>A&lt;B</title>`,
    `<style>p{}</style>` and `<article id="content">`.
  - `lineAtOffset`: in `"a\nb\r\nc"`, offset 0 → 1, offset 2 → 2, offset 5 → 3, offset past the end → 3.
  - `emptyMarkdown`: `body(for: "") == ""`.
- [ ] **Step 2: Run** `swift test --filter PreviewRendererTests`. Expected: FAIL (`PreviewRenderer` is not defined).
- [ ] **Step 3: Implement.** Call `cmark_gfm_core_extensions_ensure_registered()` once. Create a parser
  with `CMARK_OPT_SOURCEPOS` and attach the four extensions found with `cmark_find_syntax_extension`.
  Feed it, finish, then `cmark_render_html(root, options, cmark_parser_get_syntax_extensions(parser))`.
  Free with `free` / `cmark_node_free` / `cmark_parser_free`. Escape the title with a small
  `&<>"` replacement, the one hand-written helper here.
- [ ] **Step 4: Run.** Expected: PASS. Run the full `swift test` as well.
- [ ] **Step 5: Commit.** `git commit -m "feat: PreviewRenderer on cmark-gfm"`

### Task 2: Preview assets and the draft-asset scheme

**Files:** Create `DraftWriter/Preview/preview.css`, `PreviewAssets.swift`, `AssetSchemeHandler.swift`,
and `DraftWriterTests/PreviewTests.swift` (the asset tests).

**Interfaces:**
- Produces:
  ```swift
  enum PreviewAssets {
      static let scheme = "draft-asset"
      static let baseURL = URL(string: "draft-asset://doc/")!
      static func previewCSS() -> String            // preview.css with @font-face → draft-asset://app/fonts/<file>
      static func exportCSS() -> String             // preview.css with @font-face → base64 data: URIs, light only
      static func fileURL(for url: URL, documentFolder: URL?, bundle: Bundle) -> URL?
  }
  final class AssetSchemeHandler: NSObject, WKURLSchemeHandler { var documentFolder: URL? }
  ```
  `fileURL` maps `draft-asset://doc/<relative>` to `documentFolder/<relative>` (percent-decoded,
  standardised, required to stay inside the folder), and `draft-asset://app/fonts/<name>.ttf` to the
  bundle's `Fonts/<name>.ttf`. Anything else maps to nil.

- [ ] **Step 1: Write the failing tests:**
  - `resolvesDocumentRelative`: folder `/tmp/d`, `draft-asset://doc/img/a.png` → `/tmp/d/img/a.png`.
  - `decodesPercentEscapes`: `draft-asset://doc/my%20pic.png` → `/tmp/d/my pic.png`.
  - `rejectsTraversal`: `draft-asset://doc/../../etc/passwd` → nil.
  - `rejectsAbsolute`: `draft-asset://doc//etc/passwd` → nil.
  - `noFolderResolvesNothing`: folder nil → nil for a `doc` URL.
  - `resolvesBundledFont`: `draft-asset://app/fonts/iAWriterDuoS-Regular.ttf` → an existing file.
  - `exportCSSIsSelfContained`: `exportCSS()` contains `data:font/ttf;base64,` and no `draft-asset:`.
- [ ] **Step 2: Run** the hosted tests. Expected: FAIL.
- [ ] **Step 3: Implement.** The CSS has a `{{font-face}}` placeholder, replaced per variant with the four
  Duo faces plus Mono Regular for code. The handler reads the file with `Data(contentsOf:)`, sets the MIME
  type with `UTType(filenameExtension:)?.preferredMIMEType`, and answers 404 when the file is missing
  or the URL is refused.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit.** `git commit -m "feat: preview stylesheet and draft-asset scheme handler"`

### Task 3: PreviewView, the ⌘R pane and scroll sync

**Files:** Create `DraftWriter/Preview/PreviewView.swift`. Modify `DocumentWindow.swift`, `Commands.swift`,
`EditorView.swift` (report the top visible source line), `DraftWriterApp.swift` (pass `file.fileURL`).

**Interfaces:**
- Consumes: `PreviewRenderer.page/body/line`, `PreviewAssets`, `AssetSchemeHandler`.
- Produces:
  ```swift
  struct PreviewView: NSViewRepresentable { let markdown: String; let documentFolder: URL?; let topLine: Int }
  final class PreviewView.Coordinator: NSObject, WKNavigationDelegate {
      private(set) var pageLoads: Int              // full page loads; updates must not increase it
      func update(markdown: String) async          // debounced 300 ms, then replaces #content
      static func policy(for action: WKNavigationAction) -> WKNavigationActionPolicy
  }
  EditorSettings.showPreview: Bool  (⌘R, persisted)
  ```
  Scroll sync: `EditorView` reports `topLine` (the line of the first visible character) through a binding.
  The preview runs `scrollToLine(n)`, defined in the page's own script tag (app script, injected as a
  `WKUserScript`, which still runs with content JavaScript disabled). It scrolls to the last element
  whose `data-sourcepos` starts at or before line n.

- [ ] **Step 1: Write the failing hosted tests:**
  - `firstLoadShowsContent`: load `"# Title"`, wait for the navigation to finish, then
    `evaluateJavaScript("document.querySelector('#content h1').textContent")` is `"Title"`.
  - `updateKeepsSamePageLoad`: after the first load, `update(markdown: "# New")`. The content now
    reads `"New"` and `pageLoads == 1`.
  - `linkClicksOpenExternally`: `policy(for:)` is `.cancel` for a `.linkActivated` action and `.allow`
    for `.other`. Use a `WKNavigationAction` subclass stub overriding `navigationType`.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** The configuration has `defaultWebpagePreferences.allowsContentJavaScript = false`
  and `setURLSchemeHandler(handler, forURLScheme: "draft-asset")`. The first load calls
  `loadHTMLString(page, baseURL: PreviewAssets.baseURL)`. Later updates JSON-encode the body and run
  `document.getElementById('content').innerHTML = <json>`. `.linkActivated` calls
  `NSWorkspace.shared.open(url)` and cancels.
- [ ] **Step 4:** `DocumentWindow` uses an `HSplitView` with the editor and, when `showPreview` is on,
  the preview. View > "Show Preview" ⌘R.
- [ ] **Step 5: Run** the hosted suite. Expected: PASS. Commit:
  `git commit -m "feat: live preview pane with scroll sync"`

### Task 4: Export and print

**Files:** Create `DraftWriter/Export/Exporter.swift`, `DraftWriter/App/ExportCommands.swift`, `DraftWriterTests/ExportTests.swift`.
Modify `EditorSettings` (`pageSize: PageSize`, A4 or letter), `SettingsView`, `DocumentWindow`
(publishes a `FocusedValue` with the document's text, title and folder), `DraftWriterApp` (commands).

**Interfaces:**
- Produces:
  ```swift
  enum PageSize: String, CaseIterable { case a4, letter; var size: NSSize }   // a4 595.28×841.89, letter 612×792
  struct ExportSource { let markdown: String; let title: String; let documentFolder: URL? }
  @MainActor enum Exporter {
      static func html(_ source: ExportSource) -> String                         // self-contained
      static func writePDF(_ source: ExportSource, to url: URL, pageSize: PageSize) async throws
      static func print(_ source: ExportSource, pageSize: PageSize) async throws // shows the print panel
  }
  ```
- [ ] **Step 1: Write the failing hosted tests:**
  - `htmlIsSelfContained`: `html(...)` contains `<style>`, `data:font/ttf;base64,`, and no `draft-asset:`.
  - `pdfIsPaginatedA4`: `writePDF` of 3,000 words to a temp file. `PDFDocument(url:)` has `pageCount > 1`,
    and page 0's `.mediaBox` size is 595×842 (±1).
  - `pdfLetter`: with `.letter`, the page is 612×792 (±1).
  - `exportLeavesSourceUntouched`: the `ExportSource.markdown` string is unchanged afterwards. This is
    trivially true for a value type, but it pins the contract.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** An offscreen `WKWebView` (frame 800×1000) loads `PreviewRenderer.page(... css:
  PreviewAssets.exportCSS())` with the same scheme handler. After `didFinish`, build an `NSPrintInfo` with
  the paper size, 56.7 pt (2 cm) margins, and `jobDisposition = .save` with `NSPrintInfo.AttributeKey.jobSavingURL`.
  Run `webView.printOperation(with:)` with `showsPrintPanel = false` and `showsProgressPanel = false`,
  using `runModal(for:)` on a hidden window, or `run()` when a window can't be used. Print does the same
  with the panels shown.
- [ ] **Step 4: Commands.** File > "Export as HTML…" (⇧⌘E) and "Export as PDF…" go through an
  `NSSavePanel` (default name `<title>.html`/`.pdf`). File > "Print…" (⌘P) replaces the default. All are
  disabled when there's no focused document.
- [ ] **Step 5: Run** all suites. Expected: PASS. Commit: `git commit -m "feat: export HTML and PDF, print"`
- [ ] **Step 6: README.** Add the shortcuts (⌘R preview, ⇧⌘E export HTML, ⌘P print) and a note that
  relative images show in the preview only when Draft Writer can read the folder (M3's library folder
  grants that). Commit.
