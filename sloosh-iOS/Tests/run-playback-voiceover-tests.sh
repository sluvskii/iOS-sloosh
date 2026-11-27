#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/Data/Models/AllohaTranslationPolicy.swift \
  sloosh/Sources/Data/Models/CollapsModels.swift \
  sloosh/Sources/Data/Models/PlaybackSubtitle.swift \
  sloosh/Sources/Data/Repositories/CollapsParser.swift \
  sloosh/Sources/Data/Repositories/PlaybackHlsRewriter.swift \
  sloosh/Sources/Data/Repositories/HlsSegmentShield.swift \
  Tests/PlaybackVoiceoverAndAdTests.swift \
  -o "$test_dir/playback-voiceover-tests"
"$test_dir/playback-voiceover-tests"
