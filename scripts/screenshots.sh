#!/bin/sh
# Renders the README screenshots offscreen and copies them to docs/screenshots.
set -e
cd "$(dirname "$0")/.."
OUT="$HOME/Library/Containers/io.github.manuel-palacio.DraftWriter/Data/tmp/screenshots"
rm -rf "$OUT"
xcodegen generate -q
TEST_RUNNER_DRAFT_SCREENSHOTS=1 xcodebuild test -project DraftWriter.xcodeproj -scheme DraftWriter \
  -destination 'platform=macOS' -derivedDataPath .build/dd -only-testing:DraftWriterTests/ScreenshotTests -quiet
mkdir -p docs/screenshots
cp "$OUT"/*.png docs/screenshots/
ls docs/screenshots
