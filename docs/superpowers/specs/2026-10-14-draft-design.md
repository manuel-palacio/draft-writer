# Draft — design spec

Date: 2026-10-14
Status: approved in brainstorming, awaiting spec review

## Purpose

Draft is a distraction-free Markdown writing app for macOS, modelled on iA Writer. It is Manuel's
daily writing tool first: polish and reliability on his own Mac matter more than breadth. It is open
source (MIT) at `github.com/manuel-palacio/Draft`.

Success criteria:

- Writing in Draft feels as calm as iA Writer: fixed-width centred text, iA fonts, no chrome while typing.
- Files are always plain `.md`/`.txt` on disk; nothing is locked into a private format.
- Typing stays smooth on a 50,000-word document.

## Platform and dependencies

- Native macOS app, minimum macOS 15, Swift 6, SwiftUI shell + AppKit `NSTextView` (TextKit 2) editor.
- Xcode project; dependencies via Swift Package Manager.
- `swift-markdown` (Apple): parsing with source ranges, and `HTMLFormatter` for preview/export.
- Apple frameworks: `NaturalLanguage` (sentence tokenizing, word counts, part-of-speech tagging),
  `WebKit` (preview, PDF export).
- iA Writer Duo / Mono / Quattro fonts (SIL OFL, github.com/iaolo/iA-Fonts), bundled with their licence.
- No hand-rolled Markdown parser or HTML converter. `.docx` export, if added later, shells out to `pandoc`.

## Milestones

Each milestone gets its own implementation plan and ends in a usable app.

1. **M1 Editor**: core editor, typography, inline Markdown styling, themes, focus mode, typewriter
   scrolling, stats footer.
2. **M2 Reading and output**: live preview pane, HTML and PDF export, print.
3. **M3 Extras**: part-of-speech syntax highlighting, library sidebar.

## Architecture

SwiftUI `DocumentGroup` app. AppKit is confined to `EditorView`. Every text-analysis unit is a pure,
UI-free type that takes text (plus cursor/range where needed) and returns ranges or values, so it is
unit-testable without the app running.

| Unit | Responsibility | Depends on | Milestone |
|---|---|---|---|
| `MarkdownDocument` | `FileDocument`: read/write UTF-8 `.md`/`.txt` | — | M1 |
| `EditorView` | `NSViewRepresentable` hosting `NSTextView`; binds text and selection; applies attributes | AppKit | M1 |
| `MarkdownStyler` | text → `[(NSRange, MarkdownStyle)]` | swift-markdown | M1 |
| `FocusController` | (text, cursor, mode) → bright `NSRange` | NaturalLanguage | M1 |
| `TextStats` | text or selection → words, characters, reading time | NaturalLanguage | M1 |
| `Theme` / `Settings` | font, text width, appearance, focus/typewriter toggles | `@AppStorage` | M1 |
| `PreviewRenderer` | Markdown → full HTML page with stylesheet | swift-markdown | M2 |
| `PreviewView` | `WKWebView` showing rendered HTML | WebKit | M2 |
| `Exporter` | HTML file; PDF via `WKWebView.createPDF` | WebKit | M2 |
| `SyntaxHighlighter` | text → `[(NSRange, LexicalClass)]` | NaturalLanguage | M3 |
| `Library` | list/search/watch a root folder | FileManager, security-scoped bookmark | M3 |
| `LibrarySidebar` | SwiftUI sidebar over `Library` | SwiftUI | M3 |

### Window layout

Editor in the centre with a fixed text column (default ~70 characters, adjustable in Settings) and
margins that grow with the window. Optional preview pane on the right (⌘R). Optional library sidebar
on the left (⌘1). A stats footer that fades out while typing. The toolbar auto-hides and returns on
mouse movement.

## M1 — Editor

### Document

- `DocumentGroup` + `MarkdownDocument` gives open/save panels, autosave, versions, Revert, window tabs,
  Open Recent and iCloud Drive.
- Readable types: `net.daringfireball.markdown`, `public.plain-text`. New documents save as `.md`.
- Files are decoded as UTF-8. If that fails, Draft decodes as ISO Latin-1 and shows a one-time warning
  banner in the window; the file is saved back as UTF-8.
- Save errors use the standard document alerts.

### Text flow

1. The user types in the `NSTextView`.
2. The coordinator (`NSTextViewDelegate` / `NSTextStorageDelegate`) pushes the new string to the
   document binding (undo and autosave come from the document system).
3. The coordinator schedules styling.

Styling never changes the characters. It applies TextKit 2 rendering attributes, so it does not create
undo steps or mark the document as edited.

### Inline Markdown styling (`MarkdownStyler`)

- Headings: bold, sized 1.3× / 1.15× / 1.0× for levels 1 / 2 / 3–6. The `#` markers stay visible but greyed.
- Emphasis and strong: italic and bold, with the `*`/`_` markers greyed.
- Inline code and code blocks: the Mono font, with a subtle background.
- Links: the link text underlined, the URL part greyed.
- Block quotes and list markers: greyed markers, with hanging indent for lists.
- Incremental: on each edit, re-style the edited paragraph and its neighbours immediately. Run a full
  re-parse 150 ms after the last keystroke to catch constructs that span paragraphs (fenced code).

### Typography and themes

- Fonts: Duo (default), Mono or Quattro at 17 pt (adjustable 12–28), line height 1.5.
- Text column width is measured in characters of the current font. The text container inset is
  recomputed on window resize so the column stays centred.
- Light, dark and auto (follows the system) themes. Colours live in an asset catalogue with light/dark
  variants.

### Focus mode

- ⌘D cycles off → sentence → paragraph.
- `FocusController` finds the sentence (`NLTokenizer(unit: .sentence)`) or paragraph containing the
  cursor. With a selection, the bright range is the union of the units it touches.
- `EditorView` sets reduced foreground opacity (~30%) as a rendering attribute on the visible text
  outside the bright range, refreshed when the selection or text changes.

### Typewriter scrolling

- A separate toggle (⌥⌘T; plain ⌘T is the system Show Fonts command). Keeps the line being typed vertically centred.
- Implementation: top and bottom text container insets of half the visible height; after each edit or
  selection change, scroll so the caret's line rectangle is centred.

### Stats footer (`TextStats`)

- Word count (`NLTokenizer(unit: .word)`), character count, reading time at 238 wpm.
- Shows selection stats when there is a selection.
- Computed off the main thread 300 ms after the last change.

## M2 — Reading and output

### Live preview

- ⌘R toggles a right-hand `PreviewView`.
- `PreviewRenderer` produces a full HTML page: `HTMLFormatter` output inside a template with a bundled
  stylesheet (same fonts; light/dark via `prefers-color-scheme`).
- Updates 300 ms after the last change. The first load sets the page; later updates replace the body
  through `evaluateJavaScript`, so scroll position is kept.
- Scroll sync: the preview scrolls to the heading nearest the top of the editor's visible area. Headings
  get stable ids for this.
- The base URL is the document's folder, so relative images resolve. Content JavaScript is disabled
  (`WKWebpagePreferences.allowsContentJavaScript = false`; the app's own update script runs through
  `evaluateJavaScript`). Link clicks open in the default browser.
- An unsaved document has no folder, so relative images do not resolve until it is saved.

### Export and print

- File > Export as HTML…: a self-contained file with the CSS inlined.
- File > Export as PDF…: the same HTML loaded in an offscreen `WKWebView`, rendered with `createPDF`.
  Page size A4 by default (Letter selectable in Settings), with print margins.
- File > Print… uses the same HTML through `WKWebView`'s print operation.
- Export never modifies the source document.

## M3 — Extras

### Syntax highlighting

- The View menu has an on/off toggle plus toggles per class: nouns, verbs, adjectives, adverbs,
  conjunctions. Each class has its own colour with a light and a dark variant. Off by default.
- `SyntaxHighlighter` runs `NLTagger(tagSchemes: [.lexicalClass])` per paragraph. Results are cached
  by a hash of the paragraph text, so only changed paragraphs are re-tagged. Only visible paragraphs
  (plus a margin) are tagged.
- Code spans and code blocks, taken from `MarkdownStyler`'s output, are excluded.
- Language is detected per paragraph with `NLLanguageRecognizer`. Languages without lexical-class
  support are left uncoloured.
- Highlighting colour is applied as a rendering attribute. Focus-mode dimming composes with it (the
  dimmed text keeps its hue).

### Library sidebar

- ⌘1 toggles it. On first use the user chooses a root folder. The folder is stored as a
  security-scoped bookmark (app sandbox enabled, user-selected read-write entitlement).
- Shows a tree of `.md`/`.txt` files and subfolders, sortable by date modified or name.
- The search field matches file names and file contents (case-insensitive substring), scanned in the
  background.
- Watches the folder (`NSFilePresenter` / `DispatchSource`) and refreshes on change.
- Clicking a file opens it as a normal document window (or focuses it if it is already open).
- ⌘N while the sidebar has focus creates `Untitled.md` (`Untitled 2.md`, …) in the selected folder.
- Rename edits the name in place. Delete moves the file to the Trash after confirmation.
- If the bookmark goes stale (folder moved or deleted), the sidebar shows a "Choose folder…" prompt.

## Testing

- Unit tests (XCTest or Swift Testing) for the pure units:
  - `MarkdownStyler`: fixed inputs → expected ranges and styles.
  - `FocusController`: cursor positions → expected sentence/paragraph ranges, including document edges
    and empty lines.
  - `TextStats`: word/character counts and reading time, including non-English text.
  - `PreviewRenderer`: golden-file Markdown → HTML.
  - `SyntaxHighlighter`: fixed English and Swedish sentences → expected classes.
  - `Library`: list/search/create/rename against a temporary directory.
- UI smoke test: launch, new document, type, save, reopen, check the content.
- Performance check: a 50,000-word fixture document. Typing latency and re-style time are measured in a
  test with an XCTest performance baseline.

## Out of scope (for now)

iOS/iPadOS, sync beyond iCloud Drive, `.docx` export (later, via pandoc), templates, content blocks,
publishing to WordPress/Medium, auto-update (Sparkle), App Store distribution and notarization.

## Repository

- `~/Projects/Draft`, git `main`. Public GitHub repo `manuel-palacio/Draft`, created when M1's scaffold
  first builds.
- `LICENSE` (MIT), `README.md` (build instructions, feature list, font credits),
  `Resources/Fonts/` containing the iA fonts and their `LICENSE.md`.
