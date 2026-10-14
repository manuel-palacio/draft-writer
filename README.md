# Draft Writer

A calm, distraction-free Markdown editor for macOS, inspired by [iA Writer](https://ia.net/writer).
Your files stay plain `.md` text: Draft Writer only changes how they look while you write.

## Features (M1)

- Native Mac documents: autosave, versions, tabs, Open Recent, iCloud Drive
- iA Writer Duo, Mono and Quattro fonts in a centred, fixed-width column
- Markdown styled as you type: headings, bold, italic, code, links, lists, quotes (markup stays visible)
- Focus mode: dims everything but the current sentence or paragraph
- Typewriter scrolling: the line you type stays in the middle of the window
- Word count, character count and reading time (for the selection when there is one)
- Light, dark and automatic appearance

Coming next: live preview, HTML/PDF export (M2); part-of-speech highlighting and a library sidebar (M3).

## Shortcuts

| Shortcut | Action |
|---|---|
| ⌘D | Focus mode: off → sentence → paragraph |
| ⇧⌘T | Typewriter scrolling |
| ⌘, | Settings (font, size, line width, appearance) |

## Build

Requires macOS 15+ and Xcode 26+.

    brew install xcodegen
    xcodegen generate
    open DraftWriter.xcodeproj

The Xcode project is generated from `project.yml` and is not committed.

## Tests

    cd Packages/DraftKit && swift test                                   # text logic
    cd Packages/DraftKit && swift test -c release --filter PerformanceTests
    xcodebuild -scheme DraftWriter -destination 'platform=macOS' test -only-testing:DraftWriterTests

`DraftWriterUITests` drives the real app and needs an unlocked screen with UI automation allowed.
`scripts/make-fixture.swift` regenerates the 50,000-word performance fixture.

## Layout

- `Packages/DraftKit`: UI-free text logic (Markdown styling, focus ranges, stats, decoding), built on
  Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) and NaturalLanguage
- `DraftWriter/`: the SwiftUI + AppKit app
- `docs/superpowers/`: design spec and implementation plans

## Credits

Fonts: [iA Writer Duo, Mono and Quattro](https://github.com/iaolo/iA-Fonts) by Information
Architects Inc., under the SIL Open Font License (see `DraftWriter/Resources/Fonts/LICENSE.md`).

## License

MIT
