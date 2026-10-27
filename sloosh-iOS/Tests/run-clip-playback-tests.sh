#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library \
  sloosh/Sources/UI/Shared/ClipPlaybackEligibility.swift \
  sloosh/Sources/UI/Shared/PlaybackFocus.swift \
  Tests/ClipPlaybackPolicyTests.swift \
  -o "$test_dir/clip-playback-tests"
"$test_dir/clip-playback-tests"
