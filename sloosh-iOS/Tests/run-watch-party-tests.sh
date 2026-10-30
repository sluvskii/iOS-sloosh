#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
swiftc -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
  sloosh/Sources/Data/Models/WatchPartyModels.swift \
  Tests/WatchPartySyncTests.swift \
  -o "$test_dir/watch-party-tests"
"$test_dir/watch-party-tests"
